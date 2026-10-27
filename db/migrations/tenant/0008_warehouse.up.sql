-- Addresses are tenant-defined instances; an address can hold exactly one item.
ALTER TABLE products ADD CONSTRAINT products_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE raw_materials ADD CONSTRAINT raw_materials_tenant_id_id_key UNIQUE (tenant_id, id);
CREATE TABLE warehouse_layout_types (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, key text NOT NULL, name text NOT NULL,
 description text NOT NULL DEFAULT '', fields jsonb NOT NULL, code_template text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (tenant_id, id), UNIQUE (tenant_id, key)
);
CREATE TABLE warehouse_layouts (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, layout_type_id uuid NOT NULL,
 name text NOT NULL, field_values jsonb NOT NULL, code text NOT NULL,
 product_id uuid, raw_material_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (num_nonnulls(product_id, raw_material_id) <= 1),
 UNIQUE (tenant_id, id), UNIQUE (tenant_id, code),
 UNIQUE (tenant_id, product_id), UNIQUE (tenant_id, raw_material_id),
 FOREIGN KEY (tenant_id, layout_type_id) REFERENCES warehouse_layout_types(tenant_id,id),
 FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id,id),
 FOREIGN KEY (tenant_id, raw_material_id) REFERENCES raw_materials(tenant_id,id)
);
CREATE TABLE kanban_pairs (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, layout_id uuid NOT NULL,
 mode text NOT NULL CHECK (mode IN ('quantity','signal')),
 capacity_1 numeric(18,6) NOT NULL CHECK (capacity_1 > 0),
 capacity_2 numeric(18,6) NOT NULL CHECK (capacity_2 > 0),
 quantity_1 numeric(18,6) NOT NULL CHECK (quantity_1 >= 0 AND quantity_1 <= capacity_1),
 quantity_2 numeric(18,6) NOT NULL CHECK (quantity_2 >= 0 AND quantity_2 <= capacity_2),
 active_bin integer NOT NULL CHECK (active_bin IN (1,2)),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (tenant_id,id), UNIQUE (tenant_id,layout_id),
 FOREIGN KEY (tenant_id,layout_id) REFERENCES warehouse_layouts(tenant_id,id)
);
CREATE TABLE kanban_replenishments (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, pair_id uuid NOT NULL,
 bin integer NOT NULL CHECK (bin IN (1,2)),
 status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','completed')),
 created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz,
 FOREIGN KEY (tenant_id,pair_id) REFERENCES kanban_pairs(tenant_id,id)
);
CREATE UNIQUE INDEX kanban_one_open_request ON kanban_replenishments(tenant_id,pair_id,bin) WHERE status='open';
CREATE TABLE kanban_events (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, pair_id uuid NOT NULL,
 request_key text NOT NULL, payload jsonb NOT NULL, actor_id text NOT NULL,
 before_state jsonb NOT NULL, after_state jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (tenant_id,pair_id,request_key),
 FOREIGN KEY (tenant_id,pair_id) REFERENCES kanban_pairs(tenant_id,id)
);
CREATE INDEX kanban_events_history ON kanban_events(tenant_id,pair_id,created_at DESC);

-- Once bins exist, the identity and printed address must remain stable.
CREATE FUNCTION protect_kanban_location() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (NEW.product_id,NEW.raw_material_id,NEW.code,NEW.layout_type_id,NEW.field_values)
    IS DISTINCT FROM (OLD.product_id,OLD.raw_material_id,OLD.code,OLD.layout_type_id,OLD.field_values)
    AND EXISTS (SELECT 1 FROM kanban_pairs WHERE tenant_id=OLD.tenant_id AND layout_id=OLD.id) THEN
  RAISE EXCEPTION 'Kanban location is in use' USING ERRCODE='23514', CONSTRAINT='kanban_location_in_use';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_kanban_location BEFORE UPDATE ON warehouse_layouts FOR EACH ROW EXECUTE FUNCTION protect_kanban_location();

-- Legacy material writes cannot bypass the two-bin ledger. Movements update
-- bins first and the material balance in the same transaction.
CREATE FUNCTION protect_kanban_stock() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE expected double precision;
BEGIN
 SELECT (p.quantity_1+p.quantity_2)::double precision INTO expected FROM kanban_pairs p
 JOIN warehouse_layouts l ON l.tenant_id=p.tenant_id AND l.id=p.layout_id
 WHERE l.tenant_id=NEW.tenant_id AND l.raw_material_id=NEW.id;
 IF FOUND AND NEW.quantity_on_hand IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'Use Kanban movements to change stock' USING ERRCODE='23514', CONSTRAINT='kanban_stock_managed';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_kanban_stock BEFORE UPDATE OF quantity_on_hand ON raw_materials FOR EACH ROW EXECUTE FUNCTION protect_kanban_stock();

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['warehouse_layout_types','warehouse_layouts','kanban_pairs','kanban_replenishments','kanban_events'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id=nullif(current_setting(''app.current_tenant'',true),'''')::uuid) WITH CHECK (tenant_id=nullif(current_setting(''app.current_tenant'',true),'''')::uuid)',t);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO app_rw',t);
 END LOOP;
END $$;
