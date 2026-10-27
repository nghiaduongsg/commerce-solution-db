-- Product instances: actual products created against a product type. Their
-- field_values are validated against the type's fields by the application on
-- every write. Tenant-scoped and RLS-protected like every business table.

CREATE TABLE products (
    id              uuid        PRIMARY KEY,
    tenant_id       uuid        NOT NULL,
    product_type_id uuid        NOT NULL REFERENCES product_types (id) ON DELETE RESTRICT,
    status          text        NOT NULL DEFAULT 'active', -- active | archived
    field_values    jsonb       NOT NULL DEFAULT '{}',
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_products_tenant ON products (tenant_id);
CREATE INDEX idx_products_type ON products (tenant_id, product_type_id);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON products
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON products TO app_rw;
