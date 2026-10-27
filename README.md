# Commerce Solution database migrations

Standalone Liquibase repository for PostgreSQL 16. It owns the schema and
rollback SQL; the Go backend does not embed migrations or require owner credentials.
The image pins Liquibase Community 4.33.0 (including the PostgreSQL JDBC driver).

## Layout and deployment

- `changelog/primary.xml` applies tenant business tables first, then control-plane IAM tables.
- `changelog/tenant.xml` applies business tables and RLS to a premium tenant database.
- `changelog/controlplane.xml` contains IAM changes, normally included by primary.xml.
- `db/migrations/{tenant,controlplane}` preserves the original up/down SQL.

Keep this checkout beside `commerce-solution-be`, named `commerce-solution-db`.
From the backend, `docker compose up -d --build` builds this image, waits for
PostgreSQL, runs Liquibase, then starts the API. Override `MIGRATIONS_REPO_PATH`
if the checkout is elsewhere. CI should build and publish an immutable image
from this repository and run it once before deploying application instances.

To run independently, copy `.env.example` to `.env` and set the target JDBC URL
and owner credentials. The target database must already exist:

```sh
docker compose run --rm --build migrate validate
docker compose run --rm migrate update
docker compose run --rm migrate status --verbose
```

Use environment variables or the deployment secret store for credentials, never
commit them. The runtime app uses `app_rw`; this job needs a separate schema owner
and permission to create that role on a fresh cluster. The imported initial SQL
retains its development password; pre-create `app_rw` with a managed password in
production. Do not let the runtime role own the business tables or bypass RLS.

## Existing golang-migrate databases

Back up the database and stop all old application instances that run migrations.
Run the same Liquibase `update` command; do not run `changelog-sync` manually.
For each set, Liquibase checks that the legacy version table has exactly one
clean version in the supported range (tenant 1–9, control plane 1–5). Applied
versions are recorded as `MARK_RAN`; only pending versions execute. Dirty, empty,
or unknown version states fail instead of guessing. After adoption the old table
is renamed to `legacy_schema_migrations_<set>` for audit, so subsequent rollbacks
and updates use only Liquibase history. Do not restart the old Go migration runner.
An existing schema without either migration history is not automatically baselined.

## Premium databases

Create the database using your database administrator tooling, then apply only
the tenant changelog. Example using the backend's local PostgreSQL container:

```powershell
# Run in commerce-solution-be (only for a new database):
docker compose exec db createdb -U commerce tenant_globex
# Run in this repository with its .env configured for the same server:
$env:LIQUIBASE_COMMAND_URL = 'jdbc:postgresql://host.docker.internal:5433/tenant_globex'
$env:LIQUIBASE_COMMAND_CHANGELOG_FILE = 'changelog/tenant.xml'
docker compose run --rm --build migrate update
# Back in commerce-solution-be, with DATABASE_URL set to the primary app_rw DSN:
go run ./cmd/tenantctl provision --tenant globex
```

The final command verifies the migrated premium database and registers its
runtime DSN. Every primary and premium database needs its own Liquibase update
when releasing schema changes; upgrading the primary alone does not upgrade tenants.

## New migrations and rollback

Add an up SQL file and its down SQL beside the existing files; append a new
changeset in the matching changelog with a stable id/author and logical path.
Use `sqlFile splitStatements="false"` for PostgreSQL dollar-quoted functions/DO
blocks. Never edit SQL or identifiers for already-deployed changesets. The
legacy version checks apply only to the imported versions, not new changesets.
Run `validate` and `update-sql` before deployment.

```sh
docker compose run --rm migrate update-sql
docker compose run --rm migrate rollback-count-sql --count=1
# After reviewing the SQL and backing up data:
docker compose run --rm migrate rollback-count --count=1
```

Imported down SQL can destroy data. Guard/archive changesets have empty rollbacks
and count toward rollback-count; inspect history before choosing a count or tag.
Never restore the archived version tables under their original names. Code
generation in the backend reads these SQL directories; query files and generated
Go remain owned by the backend.

## Verification

```powershell
./tests/integration.ps1
```

The test uses an isolated PostgreSQL container and databases; it never connects
to the running development database. It exercises fresh primary/premium schemas,
legacy adoption, pending migrations, repeated updates, rollbacks and dirty-state
rejection. SQL was extracted from commerce-solution-be without changing its DDL.

Liquibase references: [sqlFile](https://docs.liquibase.com/reference-guide/change-types/sqlfile)
and [preconditions](https://docs.liquibase.com/community/user-guide-5-0/what-are-preconditions).
