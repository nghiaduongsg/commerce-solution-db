-- Bill of materials: the raw materials (and quantities) a product consumes,
-- used to roll up product cost. product_id is a same-module FK to products;
-- raw_material_id is a SOFT reference to the inventory module's raw_materials
-- (no cross-module FK), validated at the application layer.

CREATE TABLE product_bom_lines (
    id              uuid             PRIMARY KEY,
    tenant_id       uuid             NOT NULL,
    product_id      uuid             NOT NULL REFERENCES products (id) ON DELETE CASCADE,
    raw_material_id uuid             NOT NULL,
    quantity        double precision NOT NULL CHECK (quantity > 0),
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    UNIQUE (product_id, raw_material_id)
);
CREATE INDEX idx_product_bom_lines_tenant ON product_bom_lines (tenant_id);
CREATE INDEX idx_product_bom_lines_product ON product_bom_lines (product_id);

ALTER TABLE product_bom_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_bom_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON product_bom_lines
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON product_bom_lines TO app_rw;
