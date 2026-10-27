-- Control-plane (IAM) schema. Applied ONLY to the shared primary database.
-- These tables are accessed exclusively by the identity module: routing
-- lookups (user-by-uid, channel-by-page) must run before a tenant is known, so
-- RLS is not used here; tenant-facing IAM operations are scoped by tenant_id in
-- the identity service's queries.

CREATE TABLE tenants (
    id         uuid        PRIMARY KEY,
    name       text        NOT NULL,
    slug       text        NOT NULL UNIQUE,
    tier       text        NOT NULL DEFAULT 'paid',    -- paid | premium
    status     text        NOT NULL DEFAULT 'active',  -- active | suspended
    db_dsn     text        NOT NULL DEFAULT '',        -- premium: dedicated database DSN
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id                uuid        PRIMARY KEY,
    firebase_uid      text        NOT NULL UNIQUE,
    email             text        NOT NULL DEFAULT '',
    tenant_id         uuid        REFERENCES tenants (id) ON DELETE CASCADE, -- NULL = platform admin
    is_platform_admin boolean     NOT NULL DEFAULT false,
    status            text        NOT NULL DEFAULT 'active',
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_tenant ON users (tenant_id);

CREATE TABLE permissions (
    id          uuid PRIMARY KEY,
    key         text NOT NULL UNIQUE,
    description text NOT NULL DEFAULT ''
);

CREATE TABLE roles (
    id        uuid    PRIMARY KEY,
    key       text    NOT NULL UNIQUE,  -- platform_admin | store_admin | store_employee
    name      text    NOT NULL,
    is_system boolean NOT NULL DEFAULT true
);

CREATE TABLE role_permissions (
    role_id       uuid NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id   uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role_id   uuid NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    tenant_id uuid,  -- NULL for platform admins
    PRIMARY KEY (user_id, role_id)
);

-- Fine-grained per-employee permission grants configured by a store admin.
CREATE TABLE user_permissions (
    user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES permissions (id) ON DELETE CASCADE,
    tenant_id     uuid NOT NULL,
    PRIMARY KEY (user_id, permission_id)
);

-- Per-tenant Meta (Messenger/Instagram) connections. page_id is globally unique
-- so an inbound webhook can be routed to the owning tenant.
CREATE TABLE channel_connections (
    id                uuid        PRIMARY KEY,
    tenant_id         uuid        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    channel           text        NOT NULL,
    page_id           text        NOT NULL UNIQUE,
    app_secret        text        NOT NULL DEFAULT '', -- optional per-tenant Meta app secret
    page_access_token text        NOT NULL DEFAULT '',
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_channel_connections_tenant ON channel_connections (tenant_id);

-- Seed the permission catalog.
INSERT INTO permissions (id, key, description) VALUES
    (gen_random_uuid(), 'orders:read',             'View orders'),
    (gen_random_uuid(), 'orders:write',            'Create and modify orders'),
    (gen_random_uuid(), 'conversations:read',      'View customer conversations'),
    (gen_random_uuid(), 'conversations:write',     'Reply in customer conversations'),
    (gen_random_uuid(), 'employees:manage',        'Manage employees and their permissions'),
    (gen_random_uuid(), 'channels:manage',         'Manage Meta channel connections'),
    (gen_random_uuid(), 'tenant:configure',        'Configure the organization'),
    (gen_random_uuid(), 'platform:tenants:manage', 'Manage SaaS tenants (platform)');

-- Seed the system roles.
INSERT INTO roles (id, key, name, is_system) VALUES
    (gen_random_uuid(), 'platform_admin', 'Platform Admin', true),
    (gen_random_uuid(), 'store_admin',    'Store Admin',    true),
    (gen_random_uuid(), 'store_employee', 'Store Employee', true);

-- store_admin: every tenant-scoped permission.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.key = 'store_admin'
  AND p.key IN ('orders:read','orders:write','conversations:read','conversations:write','employees:manage','channels:manage','tenant:configure');

-- platform_admin: platform permissions (plus the is_platform_admin flag grants all at runtime).
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.key = 'platform_admin' AND p.key LIKE 'platform:%';

-- store_employee: no permissions by default; a store admin grants them per user.

GRANT SELECT, INSERT, UPDATE, DELETE ON
    tenants, users, permissions, roles, role_permissions, user_roles, user_permissions, channel_connections
    TO app_rw;
