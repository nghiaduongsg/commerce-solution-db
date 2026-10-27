-- Raw-material / inventory management permissions. store_admin gets them by
-- default; owners can delegate to employees.

INSERT INTO permissions (id, key, description) VALUES
    (gen_random_uuid(), 'raw-materials:read',  'View raw materials and inventory'),
    (gen_random_uuid(), 'raw-materials:write', 'Create, modify, and adjust raw materials')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.key = 'store_admin' AND p.key IN ('raw-materials:read', 'raw-materials:write')
ON CONFLICT DO NOTHING;
