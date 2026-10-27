-- role_permissions rows cascade when the permissions are removed.
DELETE FROM permissions WHERE key IN ('products:read', 'products:write');
