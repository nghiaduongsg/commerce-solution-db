-- Orders business tables (tenant-scoped, RLS-protected). Monetary values are
-- integer minor units.

CREATE TABLE orders (
    id                   uuid        PRIMARY KEY,
    tenant_id            uuid        NOT NULL,
    source               text        NOT NULL,
    external_reference   text        NOT NULL DEFAULT '',
    customer_external_id text        NOT NULL DEFAULT '',
    status               text        NOT NULL DEFAULT 'draft',
    currency             text        NOT NULL DEFAULT 'USD',
    total_amount_minor   bigint      NOT NULL DEFAULT 0,
    notes                text        NOT NULL DEFAULT '',
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_tenant ON orders (tenant_id);
CREATE INDEX idx_orders_customer ON orders (tenant_id, customer_external_id);

CREATE TABLE order_items (
    id               uuid    PRIMARY KEY,
    tenant_id        uuid    NOT NULL,
    order_id         uuid    NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    sku              text    NOT NULL DEFAULT '',
    name             text    NOT NULL,
    quantity         integer NOT NULL CHECK (quantity > 0),
    unit_price_minor bigint  NOT NULL DEFAULT 0,
    line_total_minor bigint  NOT NULL DEFAULT 0
);
CREATE INDEX idx_order_items_order ON order_items (order_id);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orders
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON order_items
    USING (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    )
    WITH CHECK (
        tenant_id = nullif(current_setting('app.current_tenant', true), '')::uuid
        OR coalesce(current_setting('app.bypass_tenant', true), 'off') = 'on'
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON orders, order_items TO app_rw;
