DROP TRIGGER stock_audit_material ON raw_materials;
DROP TRIGGER stock_audit_bins ON kanban_pairs;
DROP TRIGGER stock_audit_location ON warehouse_layouts;
DROP FUNCTION audit_stock_change();
DROP TABLE stock_audit_events,stock_transfers;
CREATE OR REPLACE FUNCTION protect_kanban_location() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (NEW.product_id,NEW.raw_material_id,NEW.code,NEW.layout_type_id,NEW.field_values)
    IS DISTINCT FROM (OLD.product_id,OLD.raw_material_id,OLD.code,OLD.layout_type_id,OLD.field_values)
    AND EXISTS (SELECT 1 FROM kanban_pairs WHERE tenant_id=OLD.tenant_id AND layout_id=OLD.id) THEN
  RAISE EXCEPTION 'Kanban location is in use' USING ERRCODE='23514', CONSTRAINT='kanban_location_in_use';
 END IF;
 RETURN NEW;
END $$;
