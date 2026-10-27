-- One owner-managed store profile per tenant, in the tenant's datasource.
CREATE TABLE stores (
    id uuid PRIMARY KEY,
    tenant_id uuid NOT NULL UNIQUE,
    name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 200),
    avatar_url text NOT NULL DEFAULT '',
    banner_url text NOT NULL DEFAULT '',
    description text NOT NULL DEFAULT '',
    facebook_api_key_encrypted text NOT NULL,
    llm_provider text NOT NULL DEFAULT '' CHECK (llm_provider IN ('', 'openai', 'anthropic')),
    llm_api_key_encrypted text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (facebook_api_key_encrypted <> ''),
    CHECK ((llm_provider = '') = (llm_api_key_encrypted = ''))
);

ALTER TABLE stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE stores FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stores
    USING (tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid)
    WITH CHECK (tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON stores TO app_rw;
