INSERT INTO permissions(id,key,description) VALUES(gen_random_uuid(),'stock:audit','Read permanent product and material stock audit history') ON CONFLICT(key) DO NOTHING;
INSERT INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r CROSS JOIN permissions p WHERE r.key='store_admin' AND p.key='stock:audit' ON CONFLICT DO NOTHING;
