DROP TRIGGER protect_kanban_stock ON raw_materials;
DROP FUNCTION protect_kanban_stock();
DROP TRIGGER protect_kanban_location ON warehouse_layouts;
DROP FUNCTION protect_kanban_location();
DROP TABLE kanban_events, kanban_replenishments, kanban_pairs, warehouse_layouts, warehouse_layout_types;
ALTER TABLE products DROP CONSTRAINT products_tenant_id_id_key;
ALTER TABLE raw_materials DROP CONSTRAINT raw_materials_tenant_id_id_key;
