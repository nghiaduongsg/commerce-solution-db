param([string]$Image = 'commerce-solution-db:test')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$container = "commerce-migrations-test-$suffix"
$network = "commerce-migrations-test-$suffix"

function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed: $($args[0])" }
}
function Sql([string]$Database, [string]$Statement) {
    $output = $Statement | & docker exec -i $container psql -U commerce -d $Database -v ON_ERROR_STOP=1 -At
    if ($LASTEXITCODE -ne 0) { throw "SQL failed on $Database" }
    return ($output -join "`n").Trim()
}
function Migrate([string]$Database, [string]$Changelog = 'primary', [string[]]$Command = @('update'), [switch]$ExpectFailure) {
    & docker run --rm --network $network -e "LIQUIBASE_COMMAND_URL=jdbc:postgresql://$($container):5432/$Database" `
        -e LIQUIBASE_COMMAND_USERNAME=commerce -e LIQUIBASE_COMMAND_PASSWORD=commerce `
        -e "LIQUIBASE_COMMAND_CHANGELOG_FILE=changelog/$Changelog.xml" $Image @Command
    if ($ExpectFailure) {
        if ($LASTEXITCODE -eq 0) { throw 'Unsafe legacy state was accepted' }
    } elseif ($LASTEXITCODE -ne 0) { throw "Liquibase failed on $Database" }
}
function Assert-Sql([string]$Database, [string]$Statement, [string]$Expected) {
    $actual = Sql $Database $Statement
    if ($actual -ne $Expected) { throw "Assertion on ${Database}: expected '$Expected', got '$actual' ($Statement)" }
}
function Legacy([string]$Database, [int]$TenantVersion, [int]$ControlVersion) {
    foreach ($set in @('tenant', 'controlplane')) {
        $version = if ($set -eq 'tenant') { $TenantVersion } else { $ControlVersion }
        $files = Get-ChildItem (Join-Path $repoRoot "db/migrations/$set/*.up.sql") | Sort-Object Name | Select-Object -First $version
        foreach ($file in $files) { Sql $Database (Get-Content -LiteralPath $file.FullName -Raw) | Out-Null }
        if ($version -gt 0) {
            Sql $Database "CREATE TABLE schema_migrations_$set (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL); INSERT INTO schema_migrations_$set VALUES ($version, false);" | Out-Null
        }
    }
}

try {
    Invoke-Docker build -t $Image $repoRoot
    Invoke-Docker network create $network
    Invoke-Docker run -d --name $container --network $network -e POSTGRES_USER=commerce -e POSTGRES_PASSWORD=commerce -e POSTGRES_DB=fresh postgres:16-alpine
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        & docker exec $container pg_isready -U commerce -d fresh *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Test PostgreSQL did not become ready' }
    foreach ($name in @('premium', 'legacy_full', 'legacy_partial', 'dirty', 'unknown', 'empty', 'rollback')) {
        Invoke-Docker exec $container createdb -U commerce $name
    }
    Migrate fresh primary @('validate')
    Migrate fresh
    Assert-Sql fresh "SELECT count(*) FROM databasechangelog WHERE exectype='EXECUTED'" '18'
    Assert-Sql fresh "SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='products'::regclass" 't'
    Assert-Sql fresh "SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname='app_rw'" 'f'
    Assert-Sql fresh "SELECT has_table_privilege('app_rw','products','SELECT,INSERT,UPDATE,DELETE')" 't'
    Migrate fresh
    Assert-Sql fresh 'SELECT count(*) FROM databasechangelog' '18'
    Migrate premium tenant
    Assert-Sql premium "SELECT to_regclass('public.tenants') IS NULL AND to_regclass('public.products') IS NOT NULL" 't'
    Assert-Sql premium 'SELECT count(*) FROM databasechangelog' '11'

    Legacy legacy_full 9 5
    Sql legacy_full "CREATE TABLE adoption_sentinel (value text); INSERT INTO adoption_sentinel VALUES ('preserved');" | Out-Null
    Migrate legacy_full
    Assert-Sql legacy_full "SELECT count(*) FROM databasechangelog WHERE exectype='MARK_RAN'" '14'
    Assert-Sql legacy_full 'SELECT value FROM adoption_sentinel' 'preserved'
    Assert-Sql legacy_full "SELECT to_regclass('public.schema_migrations_tenant') IS NULL AND to_regclass('public.legacy_schema_migrations_tenant') IS NOT NULL" 't'
    Migrate legacy_full
    Assert-Sql legacy_full 'SELECT value FROM adoption_sentinel' 'preserved'

    Legacy legacy_partial 3 1
    Migrate legacy_partial
    Assert-Sql legacy_partial "SELECT count(*) FROM databasechangelog WHERE exectype='MARK_RAN'" '4'
    Assert-Sql legacy_partial "SELECT to_regclass('public.stock_audit_events') IS NOT NULL" 't'

    foreach ($case in @(@('dirty', '9, true'), @('unknown', '99, false'))) {
        Sql $case[0] "CREATE TABLE schema_migrations_tenant(version bigint PRIMARY KEY, dirty boolean NOT NULL); INSERT INTO schema_migrations_tenant VALUES ($($case[1]));" | Out-Null
        Migrate $case[0] primary @('update') -ExpectFailure
        Assert-Sql $case[0] "SELECT to_regclass('public.conversations') IS NULL" 't'
    }
    Sql empty 'CREATE TABLE schema_migrations_tenant(version bigint PRIMARY KEY, dirty boolean NOT NULL);' | Out-Null
    Migrate empty primary @('update') -ExpectFailure

    # Exercise reverse-order SQL, including dollar-quoted function definitions.
    Migrate rollback
    Migrate rollback primary @('rollback-count', '--count=18')
    Assert-Sql rollback "SELECT to_regclass('public.products') IS NULL AND to_regclass('public.tenants') IS NULL" 't'
    Migrate rollback
    # An adopted database also supports rollback/update without stale legacy versions.
    Migrate legacy_full primary @('rollback-count', '--count=2')
    Migrate legacy_full
    Assert-Sql legacy_full 'SELECT value FROM adoption_sentinel' 'preserved'
    Write-Host 'PASS: fresh primary/premium, idempotency, RLS, full/partial adoption, unsafe-state rejection, rollback and reapply.'
} finally {
    & docker rm -f $container *> $null
    & docker network rm $network *> $null
}

