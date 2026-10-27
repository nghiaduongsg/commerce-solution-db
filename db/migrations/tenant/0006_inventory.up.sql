-- Inventory: tenant-defined raw material types (templates) and raw materials
-- (instances) with inventory + cost for valuation. Tenant-scoped, RLS-protected
-- like every business table.

CREATE TABLE raw_material_types (
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
CREATE INDEX idx_raw_material_types_tenant ON raw_material_types (tenant_id);

CREATE TABLE raw_material_type_fields (
    id                   uuid        PRIMARY KEY,
    tenant_id            uuid        NOT NULL,
    raw_material_type_id uuid        NOT NULL REFERENCES raw_material_types (id) ON DELETE CASCADE,
    key                  text        NOT NULL,
    label                text        NOT NULL DEFAULT '',
    data_type            text        NOT NULL, -- string | boolean | integer | float
    required             boolean     NOT NULL DEFAULT false,
    position             integer     NOT NULL DEFAULT 0,
    validation           jsonb       NOT NULL DEFAULT '{}',
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (raw_material_type_id, key)
);
CREATE INDEX idx_rmt_fields_tenant ON raw_material_type_fields (tenant_id);
CREATE INDEX idx_rmt_fields_type ON raw_material_type_fields (raw_material_type_id, position);

CREATE TABLE raw_materials (
    id                   uuid             PRIMARY KEY,
    tenant_id            uuid             NOT NULL,
    raw_material_type_id uuid             NOT NULL REFERENCES raw_material_types (id) ON DELETE RESTRICT,
    name                 text             NOT NULL,
    sku                  text             NOT NULL DEFAULT '',
    status               text             NOT NULL DEFAULT 'active',
    unit_of_measure      text             NOT NULL DEFAULT '',
    quantity_on_hand     double precision NOT NULL DEFAULT 0,
    unit_cost_minor      bigint           NOT NULL DEFAULT 0, -- cost per unit, minor units
    currency             text             NOT NULL DEFAULT 'USD',
    field_values         jsonb            NOT NULL DEFAULT '{}',
    created_at           timestamptz      NOT NULL DEFAULT now(),
    updated_at           timestamptz      NOT NULL DEFAULT now()
);
CREATE INDEX idx_raw_materials_tenant ON raw_materials (tenant_id);
CREATE INDEX idx_raw_materials_type ON raw_materials (tenant_id, raw_material_type_id);

ALTER TABLE raw_material_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE raw_material_types FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON raw_material_types
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

ALTER TABLE raw_material_type_fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE raw_material_type_fields FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON raw_material_type_fields
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

ALTER TABLE raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE raw_materials FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON raw_materials
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON raw_material_types, raw_material_type_fields, raw_materials TO app_rw;
