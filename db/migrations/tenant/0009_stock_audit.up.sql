-- Audit history deliberately has no entity FKs: deleting an item must not
-- delete its history. Runtime clients can read history but cannot rewrite it.
CREATE TABLE stock_audit_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
 item_kind text NOT NULL, item_id uuid NOT NULL, action text NOT NULL,
 actor_id text, request_id text, operation_key text, reason text NOT NULL DEFAULT '',
 before_state jsonb, after_state jsonb,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX stock_audit_item_history ON stock_audit_events(tenant_id,item_kind,item_id,created_at DESC,id);
CREATE INDEX stock_audit_tenant_history ON stock_audit_events(tenant_id,created_at DESC,id);
ALTER TABLE stock_audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_audit_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stock_audit_events USING (tenant_id=nullif(current_setting('app.current_tenant',true),'')::uuid);
GRANT SELECT ON stock_audit_events TO app_rw;

CREATE TABLE stock_transfers (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, request_key text NOT NULL,
 payload jsonb NOT NULL, receipt jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id,request_key)
);
ALTER TABLE stock_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stock_transfers
 USING (tenant_id=nullif(current_setting('app.current_tenant',true),'')::uuid)
 WITH CHECK (tenant_id=nullif(current_setting('app.current_tenant',true),'')::uuid);
GRANT SELECT,INSERT ON stock_transfers TO app_rw;

-- Security-definer is limited to trigger invocation; every insert derives the
-- tenant and item from the changed row, never from a caller-supplied SQL name.
CREATE FUNCTION audit_stock_change() RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE b jsonb; a jsonb; entity jsonb; kind text; item uuid; tid uuid;
BEGIN
 IF TG_OP <> 'INSERT' THEN b=to_jsonb(OLD); END IF;
 IF TG_OP <> 'DELETE' THEN a=to_jsonb(NEW); END IF;
 entity=coalesce(a,b); tid=(entity->>'tenant_id')::uuid;
 IF TG_TABLE_NAME='raw_materials' THEN
  IF TG_OP='UPDATE' AND b->'quantity_on_hand'=a->'quantity_on_hand' THEN RETURN NULL; END IF;
  kind='raw-material'; item=(entity->>'id')::uuid;
 ELSIF TG_TABLE_NAME='kanban_pairs' THEN
  IF TG_OP='UPDATE' AND (b->'quantity_1',b->'quantity_2',b->'layout_id',b->'mode')
    IS NOT DISTINCT FROM (a->'quantity_1',a->'quantity_2',a->'layout_id',a->'mode') THEN RETURN NULL; END IF;
  SELECT CASE WHEN l.product_id IS NULL THEN 'raw-material' ELSE 'product' END,
         coalesce(l.product_id,l.raw_material_id) INTO kind,item
  FROM public.warehouse_layouts l WHERE l.tenant_id=tid
   AND l.id IN ((a->>'layout_id')::uuid,(b->>'layout_id')::uuid)
   AND coalesce(l.product_id,l.raw_material_id) IS NOT NULL LIMIT 1;
 ELSE
  IF TG_OP='UPDATE' AND (b->'product_id',b->'raw_material_id',b->'code')
    IS NOT DISTINCT FROM (a->'product_id',a->'raw_material_id',a->'code') THEN RETURN NULL; END IF;
  -- A reassignment produces records for both affected items.
  FOR kind,item IN
   SELECT DISTINCT x.kind,x.item FROM (VALUES
    ('product',(b->>'product_id')::uuid),('product',(a->>'product_id')::uuid),
    ('raw-material',(b->>'raw_material_id')::uuid),('raw-material',(a->>'raw_material_id')::uuid)
   ) AS x(kind,item) WHERE x.item IS NOT NULL
  LOOP
   INSERT INTO public.stock_audit_events(tenant_id,item_kind,item_id,action,actor_id,request_id,operation_key,reason,before_state,after_state)
   VALUES(tid,kind,item,'location_'||lower(TG_OP),nullif(current_setting('app.actor_id',true),''),
    nullif(current_setting('app.request_id',true),''),nullif(current_setting('app.operation_key',true),''),
    coalesce(current_setting('app.audit_reason',true),''),b,a);
  END LOOP;
  RETURN NULL;
 END IF;
 IF item IS NOT NULL THEN
  INSERT INTO public.stock_audit_events(tenant_id,item_kind,item_id,action,actor_id,request_id,operation_key,reason,before_state,after_state)
  VALUES(tid,kind,item,TG_TABLE_NAME||'_'||lower(TG_OP),nullif(current_setting('app.actor_id',true),''),
   nullif(current_setting('app.request_id',true),''),nullif(current_setting('app.operation_key',true),''),
   coalesce(current_setting('app.audit_reason',true),''),b,a);
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER stock_audit_material AFTER INSERT OR UPDATE OR DELETE ON raw_materials FOR EACH ROW EXECUTE FUNCTION audit_stock_change();
CREATE TRIGGER stock_audit_bins AFTER INSERT OR UPDATE OR DELETE ON kanban_pairs FOR EACH ROW EXECUTE FUNCTION audit_stock_change();
CREATE TRIGGER stock_audit_location AFTER INSERT OR UPDATE OR DELETE ON warehouse_layouts FOR EACH ROW EXECUTE FUNCTION audit_stock_change();

-- A transfer first moves the pair to an empty destination, then moves the item.
-- Existing occupied Kanban locations remain protected against reassignment.
CREATE OR REPLACE FUNCTION protect_kanban_location() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (OLD.product_id IS NOT NULL OR OLD.raw_material_id IS NOT NULL)
    AND (NEW.product_id,NEW.raw_material_id,NEW.code,NEW.layout_type_id,NEW.field_values)
    IS DISTINCT FROM (OLD.product_id,OLD.raw_material_id,OLD.code,OLD.layout_type_id,OLD.field_values)
    AND EXISTS (SELECT 1 FROM kanban_pairs WHERE tenant_id=OLD.tenant_id AND layout_id=OLD.id) THEN
  RAISE EXCEPTION 'Kanban location is in use' USING ERRCODE='23514', CONSTRAINT='kanban_location_in_use';
 END IF;
 RETURN NEW;
END $$;
