-- Messaging business tables. This migration set is applied to the shared
-- primary database (pooled/paid tenants) AND to every premium tenant's
-- dedicated database. Tenant isolation is enforced by Row-Level Security keyed
-- on the `app.current_tenant` GUC set per request.

-- Least-privilege runtime role. The application connects as this NON-superuser
-- role so that FORCE ROW LEVEL SECURITY actually constrains it (superusers
-- bypass RLS). Created idempotently; roles are cluster-scoped.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_rw') THEN
        CREATE ROLE app_rw LOGIN PASSWORD 'app_rw';
    END IF;
END$$;
GRANT USAGE ON SCHEMA public TO app_rw;

CREATE TABLE conversations (
    id                   uuid        PRIMARY KEY,
    tenant_id            uuid        NOT NULL,
    channel              text        NOT NULL,
    page_id              text        NOT NULL,
    customer_external_id text        NOT NULL,
    status               text        NOT NULL DEFAULT 'open',
    last_message_at      timestamptz NOT NULL DEFAULT now(),
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, channel, page_id, customer_external_id)
);
CREATE INDEX idx_conversations_tenant ON conversations (tenant_id);

CREATE TABLE messages (
    id                   uuid        PRIMARY KEY,
    tenant_id            uuid        NOT NULL,
    conversation_id      uuid        NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    direction            text        NOT NULL,
    sender_role          text        NOT NULL,
    content              text        NOT NULL DEFAULT '',
    raw_payload          jsonb,
    llm_action           text        NOT NULL DEFAULT '',
    external_message_id  text,
    order_id             text        NOT NULL DEFAULT '',
    created_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_conversation ON messages (conversation_id, created_at);
-- Dedupe inbound webhook retries per tenant.
CREATE UNIQUE INDEX uq_messages_tenant_external_id
    ON messages (tenant_id, external_message_id)
    WHERE external_message_id IS NOT NULL;

-- Row-Level Security: confine every row to the request's tenant. FORCE so the
-- table owner is subject too; the app connects as the non-superuser app_rw.
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON conversations
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON messages
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON conversations, messages TO app_rw;
