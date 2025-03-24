-- File: create_ring2all.sql
-- Description: Creates and configures the ring2all database for FreeSWITCH integration.
--              Includes schemas (core, auth), tables for tenants, SIP users, IVRs, dialplans, and SIP profiles.
--              Also sets up user privileges, triggers, and initial demo tenant.
-- Usage: sudo -u postgres psql -d postgres -f create_ring2all.sql
-- Prerequisites: Replace $r2a_database, $r2a_user, and $r2a_password with actual values before running.

-- Create the ring2all database if it does not exist
CREATE DATABASE $r2a_database;

-- Connect to the ring2all database
\connect $r2a_database

-- Create schemas for modular design
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS auth;

-- Enable useful PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA public;

-- Create the role if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$r2a_user') THEN
        EXECUTE 'CREATE ROLE ' || quote_ident('$r2a_user') || ' WITH LOGIN PASSWORD ' || quote_literal('$r2a_password');
    END IF;
END $$;

-- Grant privileges on the database
GRANT ALL PRIVILEGES ON DATABASE $r2a_database TO $r2a_user;

-- Grant full access on schemas
GRANT ALL PRIVILEGES ON SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON SCHEMA core TO $r2a_user;
GRANT ALL PRIVILEGES ON SCHEMA auth TO $r2a_user;

-- Grant full privileges on all current tables and sequences
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO $r2a_user;

GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA auth TO $r2a_user;

-- Grant privileges on all existing functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO $r2a_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core TO $r2a_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO $r2a_user;

-- Ensure full access to future tables and sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON TABLES TO $r2a_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON SEQUENCES TO $r2a_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA core
GRANT ALL PRIVILEGES ON TABLES TO $r2a_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA core
GRANT ALL PRIVILEGES ON SEQUENCES TO $r2a_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA auth
GRANT ALL PRIVILEGES ON TABLES TO $r2a_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
GRANT ALL PRIVILEGES ON SEQUENCES TO $r2a_user;

-- === TABLES, INDEXES, TRIGGERS, AND DEMO DATA CONTINUE ===
-- === BEGIN FULL SCHEMA DEFINITION ===

-- Create the tenants table to store tenant information
CREATE TABLE tenants (
    tenant_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),          -- Unique identifier for the tenant, auto-generated UUID
    parent_tenant_uuid UUID,                                          -- Optional reference to a parent tenant for hierarchical structure
    name TEXT NOT NULL UNIQUE,                                        -- Unique name of the tenant (e.g., company name)
    domain_name TEXT NOT NULL UNIQUE,                                 -- Unique domain name used in FreeSWITCH (e.g., sip.example.com)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the tenant is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable for system inserts)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable),
    CONSTRAINT fk_tenants_parent                                      -- Foreign key to support tenant hierarchy
        FOREIGN KEY (parent_tenant_uuid) REFERENCES tenants (tenant_uuid) 
        ON DELETE SET NULL                                            -- Sets parent_tenant_uuid to NULL if parent is deleted
);

-- Indexes for tenants
CREATE INDEX idx_tenants_name ON tenants (name);
CREATE INDEX idx_tenants_domain_name ON tenants (domain_name);
CREATE INDEX idx_tenants_enabled ON tenants (enabled);
CREATE INDEX idx_tenants_insert_date ON tenants (insert_date);

-- Create the tenant_settings table for tenant-specific configurations
CREATE TABLE tenant_settings (
    tenant_setting_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the setting, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    name TEXT NOT NULL,                                               -- Setting name (e.g., "max_calls")
    value TEXT NOT NULL,                                              -- Setting value (e.g., "100")
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable),
    CONSTRAINT fk_tenant_settings_tenants                             -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES tenants (tenant_uuid) 
        ON DELETE CASCADE,                                            -- Deletes settings when a tenant is removed
    CONSTRAINT unique_tenant_setting UNIQUE (tenant_uuid, name)       -- Ensures each tenant has unique setting names
);

-- Indexes for tenant_settings
CREATE INDEX idx_tenant_settings_tenant_uuid ON tenant_settings (tenant_uuid);
CREATE INDEX idx_tenant_settings_name ON tenant_settings (name);
CREATE INDEX idx_tenant_settings_insert_date ON tenant_settings (insert_date);

-- ===========================
-- Table: core.sip_profiles
-- Description: Defines SIP profiles with multi-transport and port support
-- ===========================

CREATE TABLE core.sip_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                      -- Unique identifier for the SIP profile
    name TEXT NOT NULL UNIQUE,                                           -- Unique name for the SIP profile (e.g., internal, external)
    tenant_id UUID NOT NULL REFERENCES core.tenant(id) ON DELETE CASCADE, -- Tenant association for multi-tenant environments
    description TEXT,                                                    -- Optional profile description
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Indicates if the profile is enabled or not
    bind_address TEXT,                                                   -- Bind address (e.g., 0.0.0.0:5060)
    sip_port INTEGER,                                                    -- SIP port number (e.g., 5060, 7443)
    transport TEXT,                                                      -- Transport type (e.g., udp, tcp, tls, ws, wss)
    tls_enabled BOOLEAN DEFAULT FALSE,                                   -- Whether TLS is enabled for the profile

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp with timezone
    insert_user UUID,                                                    -- UUID of the user who created the record (nullable for system inserts)
    update_date TIMESTAMPTZ,                                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID                                                     -- UUID of the user who last updated the record (nullable)
);

-- Indexes for core.sip_profiles
CREATE INDEX idx_sip_profiles_tenant_id ON core.sip_profiles (tenant_id);      -- Index for filtering by tenant
CREATE INDEX idx_sip_profiles_insert_user ON core.sip_profiles (insert_user);  -- Index for querying creator
CREATE INDEX idx_sip_profiles_update_user ON core.sip_profiles (update_user);  -- Index for querying last updater

-- ===========================
-- Table: core.sip_profile_settings
-- Description: Key-value settings for SIP profiles
-- ===========================

CREATE TABLE core.sip_profile_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique identifier for the SIP profile setting
    sip_profile_id UUID NOT NULL REFERENCES core.sip_profiles(id) ON DELETE CASCADE, -- Foreign key to the SIP profile
    name TEXT NOT NULL,                                                   -- Name of the setting (e.g., rtp-ip, sip-ip)
    value TEXT NOT NULL,                                                  -- Value of the setting
    type TEXT,                                                            -- Optional type or category (e.g., media, auth, network)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Indicates if the setting is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Creation timestamp with timezone
    insert_user UUID,                                                     -- UUID of the user who created the record (nullable)
    update_date TIMESTAMPTZ,                                              -- Last update timestamp with timezone (updated by trigger)
    update_user UUID                                                      -- UUID of the user who last updated the record (nullable)
);

-- Indexes for core.sip_profile_settings
CREATE INDEX idx_sip_profile_settings_profile_id ON core.sip_profile_settings (sip_profile_id); -- Index for joining with SIP profiles
CREATE INDEX idx_sip_profile_settings_name ON core.sip_profile_settings (name);                 -- Index for querying by setting name
CREATE INDEX idx_sip_profile_settings_insert_user ON core.sip_profile_settings (insert_user);   -- Index for querying creator
CREATE INDEX idx_sip_profile_settings_update_user ON core.sip_profile_settings (update_user);   -- Index for querying last updater

-- ===========================
-- Table: core.gateways
-- Description: Defines SIP gateways per tenant, linked optionally to a SIP profile
-- ===========================

CREATE TABLE core.gateways (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                      -- Unique identifier for the gateway
    tenant_id UUID NOT NULL REFERENCES core.tenant(id) ON DELETE CASCADE, -- Tenant association for multi-tenant environments
    sip_profile_id UUID REFERENCES core.sip_profiles(id) ON DELETE SET NULL, -- Associated SIP profile (nullable)
    name TEXT NOT NULL,                                                 -- Name of the gateway (e.g., provider1)
    description TEXT,                                                   -- Optional description of the gateway
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                              -- Indicates if the gateway is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                     -- Creation timestamp with timezone
    insert_user UUID,                                                   -- UUID of the user who created the record (nullable)
    update_date TIMESTAMPTZ,                                            -- Last update timestamp with timezone (updated by trigger)
    update_user UUID                                                    -- UUID of the user who last updated the record (nullable)
);

-- Indexes for core.gateways
CREATE INDEX idx_gateways_tenant_id ON core.gateways (tenant_id);            -- Index for filtering by tenant
CREATE INDEX idx_gateways_sip_profile_id ON core.gateways (sip_profile_id);  -- Index for joining with SIP profiles
CREATE INDEX idx_gateways_insert_user ON core.gateways (insert_user);        -- Index for querying creator
CREATE INDEX idx_gateways_update_user ON core.gateways (update_user);        -- Index for querying last updater

-- ===========================
-- Table: core.gateway_settings
-- Description: Key-value settings for SIP gateways
-- ===========================

CREATE TABLE core.gateway_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique identifier for the gateway setting
    gateway_id UUID NOT NULL REFERENCES core.gateways(id) ON DELETE CASCADE, -- Foreign key to the SIP gateway
    name TEXT NOT NULL,                                                   -- Name of the setting (e.g., username, password, proxy)
    value TEXT NOT NULL,                                                  -- Value of the setting
    type TEXT,                                                            -- Optional type or category (e.g., auth, transport, registration)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Indicates if the setting is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Creation timestamp with timezone
    insert_user UUID,                                                     -- UUID of the user who created the record (nullable)
    update_date TIMESTAMPTZ,                                              -- Last update timestamp with timezone (updated by trigger)
    update_user UUID                                                      -- UUID of the user who last updated the record (nullable)
);

-- Indexes for core.gateway_settings
CREATE INDEX idx_gateway_settings_gateway_id ON core.gateway_settings (gateway_id);     -- Index for joining with gateways
CREATE INDEX idx_gateway_settings_name ON core.gateway_settings (name);                 -- Index for querying by setting name
CREATE INDEX idx_gateway_settings_insert_user ON core.gateway_settings (insert_user);   -- Index for querying creator
CREATE INDEX idx_gateway_settings_update_user ON core.gateway_settings (update_user);   -- Index for querying last updater

-- ===========================
-- Table: core.sip_users
-- Description: Defines SIP users (extensions) per tenant
-- ===========================

CREATE TABLE core.sip_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                      -- Unique identifier for the SIP user
    tenant_id UUID NOT NULL REFERENCES core.tenant(id) ON DELETE CASCADE, -- Tenant association for multi-tenant environments
    username TEXT NOT NULL,                                              -- SIP username (e.g., extension number)
    password TEXT NOT NULL,                                              -- SIP password (should be securely hashed)
    voicemail_enabled BOOLEAN DEFAULT FALSE,                             -- Whether voicemail is enabled for this user
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Indicates if the SIP user is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp with timezone
    insert_user UUID,                                                    -- UUID of the user who created the record (nullable)
    update_date TIMESTAMPTZ,                                             -- Last update timestamp with timezone
    update_user UUID                                                     -- UUID of the user who last updated the record (nullable)
);

-- Indexes for core.sip_users
CREATE INDEX idx_sip_users_tenant_id ON core.sip_users (tenant_id);              -- Index for filtering by tenant
CREATE INDEX idx_sip_users_username ON core.sip_users (username);                -- Index for querying by SIP username
CREATE INDEX idx_sip_users_insert_user ON core.sip_users (insert_user);          -- Index for querying creator
CREATE INDEX idx_sip_users_update_user ON core.sip_users (update_user);          -- Index for querying last updater

-- ===========================
-- Table: core.sip_user_settings
-- Description: Key-value settings for SIP users
-- ===========================

CREATE TABLE core.sip_user_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique identifier for the SIP user setting
    sip_user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- Foreign key to the SIP user
    name TEXT NOT NULL,                                                   -- Name of the setting (e.g., caller-id, auth-acl)
    value TEXT NOT NULL,                                                  -- Value of the setting
    type TEXT,                                                            -- Optional type or category (e.g., auth, codec, network)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Indicates if the setting is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Creation timestamp with timezone
    insert_user UUID,                                                     -- UUID of the user who created the record (nullable)
    update_date TIMESTAMPTZ,                                              -- Last update timestamp with timezone
    update_user UUID                                                      -- UUID of the user who last updated the record (nullable)
);

-- Indexes for core.sip_user_settings
CREATE INDEX idx_sip_user_settings_user_id ON core.sip_user_settings (sip_user_id);     -- Index for joining with SIP users
CREATE INDEX idx_sip_user_settings_name ON core.sip_user_settings (name);               -- Index for querying by setting name
CREATE INDEX idx_sip_user_settings_insert_user ON core.sip_user_settings (insert_user); -- Index for querying creator
CREATE INDEX idx_sip_user_settings_update_user ON core.sip_user_settings (update_user); -- Index for querying last updater

-- ===========================
-- Table: core.voicemail
-- Description: Voicemail inbox configuration per SIP user
-- ===========================

CREATE TABLE core.voicemail (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the voicemail box
    sip_user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- Link to the SIP user that owns this mailbox
    tenant_id UUID NOT NULL REFERENCES core.tenant(id) ON DELETE CASCADE, -- Tenant that owns this voicemail box
    password TEXT NOT NULL,                                               -- Voicemail PIN/password
    greeting TEXT,                                                        -- Optional path or reference to custom greeting
    email TEXT,                                                           -- Optional email for voicemail to email
    max_messages INTEGER DEFAULT 100,                                     -- Maximum number of voicemail messages allowed
    storage_path TEXT,                                                    -- Optional path override for voicemail message storage
    notification_enabled BOOLEAN DEFAULT TRUE,                            -- Whether email or webhook notification is enabled
    transcribe_enabled BOOLEAN DEFAULT FALSE,                             -- Whether speech-to-text transcription is enabled
    email_attachment BOOLEAN DEFAULT TRUE,                                -- Whether to include the audio file in email notifications
    email_template TEXT,                                                  -- Optional template name for email body
    language TEXT DEFAULT 'en',                                           -- Preferred language for prompts (e.g., en, es, fr)
    timezone TEXT DEFAULT 'UTC',                                          -- Timezone for timestamps in notifications
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Whether the voicemail is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Creation timestamp with timezone
    insert_user UUID,                                                     -- UUID of the user who created the record
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- UUID of the user who last updated the record
);

-- Indexes for core.voicemail
CREATE INDEX idx_voicemail_sip_user_id ON core.voicemail (sip_user_id);     -- Index for linking to SIP users
CREATE INDEX idx_voicemail_tenant_id ON core.voicemail (tenant_id);         -- Index for filtering by tenant
CREATE INDEX idx_voicemail_insert_user ON core.voicemail (insert_user);     -- Index for querying creator
CREATE INDEX idx_voicemail_update_user ON core.voicemail (update_user);     -- Index for querying updater



-- Function: core.set_update_timestamp()
-- Description: Automatically sets update_date to current timestamp on UPDATE

CREATE OR REPLACE FUNCTION core.set_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.update_date := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_update_sip_profiles
BEFORE UPDATE ON core.sip_profiles
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_sip_profile_settings
BEFORE UPDATE ON core.sip_profile_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_sip_users
BEFORE UPDATE ON core.sip_users
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_sip_user_settings
BEFORE UPDATE ON core.sip_user_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_voicemail
BEFORE UPDATE ON core.voicemail
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();



