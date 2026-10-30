-- Credentials are encrypted in the application and bound to tenant + Page.
CREATE TABLE inbox_connections (
 tenant_id uuid PRIMARY KEY, page_id text NOT NULL, page_name text NOT NULL,
 token_ciphertext text NOT NULL, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE inbox_thread_state (
 tenant_id uuid NOT NULL, page_id text NOT NULL, thread_id text NOT NULL,
 status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved')),
 read_at timestamptz, PRIMARY KEY (tenant_id,page_id,thread_id)
);
-- Reserve before contacting Meta. An ambiguous timeout must never resend automatically.
CREATE TABLE inbox_sends (
 tenant_id uuid NOT NULL, request_id uuid NOT NULL, page_id text NOT NULL,
 thread_id text NOT NULL, content_hash text NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','sent','failed','unknown')),
 message_id text, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (tenant_id,request_id)
);
DO $rls$
DECLARE tbl text;
BEGIN
 FOREACH tbl IN ARRAY ARRAY['inbox_connections','inbox_thread_state','inbox_sends'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tbl);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tbl);
  EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = nullif(current_setting(''app.current_tenant'',true),'''')::uuid) WITH CHECK (tenant_id = nullif(current_setting(''app.current_tenant'',true),'''')::uuid)',tbl);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO app_rw',tbl);
 END LOOP;
END $rls$;
