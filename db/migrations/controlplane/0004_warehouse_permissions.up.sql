INSERT INTO permissions(id,key,description) VALUES
 (gen_random_uuid(),'warehouse:read','View warehouse locations and labels'),
 (gen_random_uuid(),'warehouse:write','Manage warehouse locations and item assignments'),
 (gen_random_uuid(),'kanban:read','View two-bin stock and replenishment requests'),
 (gen_random_uuid(),'kanban:write','Record two-bin consumption and replenishment')
ON CONFLICT(key) DO NOTHING;
INSERT INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r CROSS JOIN permissions p
WHERE r.key='store_admin' AND p.key IN ('warehouse:read','warehouse:write','kanban:read','kanban:write')
ON CONFLICT DO NOTHING;
