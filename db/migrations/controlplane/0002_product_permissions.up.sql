-- Product management permissions. Added to the catalog so store owners can
-- delegate product management to employees; store_admin gets them by default.

INSERT INTO permissions (id, key, description) VALUES
    (gen_random_uuid(), 'products:read',  'View products'),
    (gen_random_uuid(), 'products:write', 'Create and modify products')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.key = 'store_admin' AND p.key IN ('products:read', 'products:write')
ON CONFLICT DO NOTHING;
