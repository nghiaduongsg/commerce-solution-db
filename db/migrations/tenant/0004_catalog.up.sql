-- Catalog: tenant-defined product types (templates) and their typed, validated
-- fields. Tenant-scoped and RLS-protected, same pattern as orders.

CREATE TABLE product_types (
    id          uuid        PRIMARY KEY,
    tenant_id   uuid        NOT NULL,
    key         text        NOT NULL,
    name        text        NOT NULL,
    description text        NOT NULL DEFAULT '',
    status      text        NOT NULL DEFAULT 'active', -- active | archived
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, key)
);
CREATE INDEX idx_product_types_tenant ON product_types (tenant_id);

CREATE TABLE product_type_fields (
    id              uuid        PRIMARY KEY,
    tenant_id       uuid        NOT NULL,
    product_type_id uuid        NOT NULL REFERENCES product_types (id) ON DELETE CASCADE,
    key             text        NOT NULL,
    label           text        NOT NULL DEFAULT '',
    data_type       text        NOT NULL, -- string | boolean | integer | float
    required        boolean     NOT NULL DEFAULT false,
    position        integer     NOT NULL DEFAULT 0,
    validation      jsonb       NOT NULL DEFAULT '{}',
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_type_id, key)
);
CREATE INDEX idx_product_type_fields_tenant ON product_type_fields (tenant_id);
CREATE INDEX idx_product_type_fields_type ON product_type_fields (product_type_id, position);

ALTER TABLE product_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_types FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON product_types
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

ALTER TABLE product_type_fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_type_fields FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON product_type_fields
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON product_types, product_type_fields TO app_rw;
