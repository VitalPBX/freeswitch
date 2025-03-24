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
    type TEXT,                                                            -- Optional setting category (e.g., media, auth, network)
    value TEXT NOT NULL,                                                  -- Value of the setting
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
    type TEXT,                                                            -- Optional type or category (e.g., auth, transport, registration)
    value TEXT NOT NULL,                                                  -- Value of the setting
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
    type TEXT,                                                            -- Optional type or category (e.g., auth, codec, network)
    value TEXT NOT NULL,                                                  -- Value of the setting
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

-- ===========================
-- Table: core.dialplan
-- Description: Defines dialplan contexts and execution order
-- ===========================

CREATE TABLE core.dialplan (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                         -- Unique identifier for the dialplan
    tenant_id UUID NOT NULL REFERENCES core.tenant(id) ON DELETE CASCADE,   -- Tenant that owns this dialplan
    name TEXT NOT NULL,                                                     -- Dialplan name (e.g., default, public)
    context TEXT NOT NULL,                                                  -- Context name used in FreeSWITCH
    order INTEGER DEFAULT 100,                                              -- Execution order of this dialplan
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                  -- Whether this dialplan is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                         -- Creation timestamp
    insert_user UUID,                                                       -- UUID of user who created the record
    update_date TIMESTAMPTZ,                                                -- Last update timestamp
    update_user UUID                                                        -- UUID of user who last updated the record
);

-- Indexes for core.dialplan
CREATE INDEX idx_dialplan_tenant_id ON core.dialplan (tenant_id);             -- For filtering by tenant
CREATE INDEX idx_dialplan_name ON core.dialplan (name);                       -- For lookups by dialplan name
CREATE INDEX idx_dialplan_insert_user ON core.dialplan (insert_user);         -- For querying creator
CREATE INDEX idx_dialplan_update_user ON core.dialplan (update_user);         -- For querying updater

-- ===========================
-- Table: core.dialplan_settings
-- Description: Key-value settings for dialplans
-- ===========================

CREATE TABLE core.dialplan_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                          -- Unique identifier for the dialplan setting
    dialplan_id UUID NOT NULL REFERENCES core.dialplan(id) ON DELETE CASCADE, -- Foreign key to the dialplan
    name TEXT NOT NULL,                                                     -- Setting name (e.g., condition, action, regex)
    value TEXT NOT NULL,                                                    -- Setting value (e.g., destination_number ^\d+$)
    type TEXT,                                                              -- Optional category (e.g., condition, action, anti-action)
    setting_scope TEXT,                                                     -- Optional grouping or priority (e.g., main, fallback)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                  -- Whether this setting is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                         -- Creation timestamp
    insert_user UUID,                                                       -- UUID of user who created the setting
    update_date TIMESTAMPTZ,                                                -- Last update timestamp
    update_user UUID                                                        -- UUID of user who last updated the setting
);

-- Indexes for core.dialplan_settings
CREATE INDEX idx_dialplan_settings_dialplan_id ON core.dialplan_settings (dialplan_id); -- For joining with dialplans
CREATE INDEX idx_dialplan_settings_name ON core.dialplan_settings (name);               -- For querying by setting name
CREATE INDEX idx_dialplan_settings_insert_user ON core.dialplan_settings (insert_user); -- For querying creator
CREATE INDEX idx_dialplan_settings_update_user ON core.dialplan_settings (update_user); -- For querying updater

-- ===========================
-- Table: core.ivr
-- Description: Defines IVR menus for call routing and DTMF input
-- ===========================

CREATE TABLE core.ivr (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the IVR menu
    tenant_id UUID NOT NULL REFERENCES core.tenant(id) ON DELETE CASCADE, -- Tenant that owns this IVR
    name TEXT NOT NULL,                                                  -- Human-readable name for the IVR menu
    greet_long TEXT,                                                     -- Path or name of the long greeting audio file
    greet_short TEXT,                                                    -- Path or name of the short greeting audio file
    invalid_sound TEXT,                                                  -- Sound played on invalid input
    exit_sound TEXT,                                                     -- Sound played on exit
    timeout INTEGER DEFAULT 5,                                           -- Seconds to wait for DTMF input
    max_failures INTEGER DEFAULT 3,                                      -- Maximum number of failures before exit
    max_timeouts INTEGER DEFAULT 3,                                      -- Maximum number of timeouts before exit
    direct_dial BOOLEAN DEFAULT FALSE,                                   -- Whether to allow direct extension dialing
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Indicates if the IVR is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- UUID of user who created the IVR
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- UUID of user who last updated the IVR
);

-- Indexes for core.ivr
CREATE INDEX idx_ivr_tenant_id ON core.ivr (tenant_id);               -- For filtering IVRs by tenant
CREATE INDEX idx_ivr_name ON core.ivr (name);                         -- For querying IVR by name
CREATE INDEX idx_ivr_insert_user ON core.ivr (insert_user);           -- By creator
CREATE INDEX idx_ivr_update_user ON core.ivr (update_user);           -- By last updater

-- ===========================
-- Table: core.ivr_settings
-- Description: Advanced IVR options and DTMF mappings, supporting submenus and dynamic logic
-- ===========================

CREATE TABLE core.ivr_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique identifier for the IVR setting
    ivr_id UUID NOT NULL REFERENCES core.ivr(id) ON DELETE CASCADE,       -- Foreign key to the IVR
    digits TEXT NOT NULL,                                                 -- DTMF digits pressed (e.g., "1", "*", "0")
    action TEXT NOT NULL,                                                 -- Action to perform (e.g., transfer, playback, hangup, submenu, set)
    destination TEXT,                                                     -- Destination value (e.g., extension, dialplan, IVR ID for submenu, variable name)
    condition TEXT,                                                       -- Optional condition (e.g., ${caller_id_number} =~ ^123)
    break_on_match BOOLEAN DEFAULT FALSE,                                 -- Whether to stop evaluation after this match
    order INTEGER DEFAULT 100,                                            -- Execution order of this setting
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Whether this DTMF option is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Creation timestamp
    insert_user UUID,                                                     -- Creator UUID
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Last updater UUID
);

-- Indexes for core.ivr_settings
CREATE INDEX idx_ivr_settings_ivr_id ON core.ivr_settings (ivr_id);       -- For joining with IVRs
CREATE INDEX idx_ivr_settings_digits ON core.ivr_settings (digits);       -- For fast lookup of digit mappings
CREATE INDEX idx_ivr_settings_insert_user ON core.ivr_settings (insert_user); -- Creator index
CREATE INDEX idx_ivr_settings_update_user ON core.ivr_settings (update_user); -- Updater index

-- ===========================
-- Table: core.ring_groups
-- Description: Base definition for ring groups
-- ===========================

CREATE TABLE core.ring_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the ring group
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant ID
    name TEXT NOT NULL,                                                  -- Name of the ring group
    description TEXT,                                                    -- Optional description
    strategy TEXT NOT NULL DEFAULT 'simultaneous',                       -- Ring strategy: simultaneous, sequence, enterprise
    ring_timeout INTEGER DEFAULT 20,                                     -- Timeout per user before fallback
    skip_busy BOOLEAN DEFAULT FALSE,                                     -- Skip user if busy
    fallback_destination TEXT,                                           -- Optional fallback destination
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether the ring group is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.ring_groups
CREATE INDEX idx_ring_groups_tenant_id ON core.ring_groups (tenant_id);  -- Index for tenant-based filtering

-- ===========================
-- Table: core.ring_group_settings
-- Description: Custom settings for ring groups
-- ===========================

CREATE TABLE core.ring_group_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the setting
    ring_group_id UUID NOT NULL REFERENCES core.ring_groups(id) ON DELETE CASCADE, -- Associated ring group
    category TEXT,                                                        -- Optional setting category
    name TEXT NOT NULL,                                                  -- Setting name
    value TEXT NOT NULL,                                                 -- Setting value
    setting_type TEXT DEFAULT 'profile',                                 -- Setting type: profile, media, timeout, etc.

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.ring_group_settings
CREATE INDEX idx_ring_group_settings_group_id ON core.ring_group_settings (ring_group_id); -- Fast lookup by ring group
CREATE INDEX idx_ring_group_settings_name ON core.ring_group_settings (name);              -- Useful for filtering by setting

-- ===========================
-- Table: core.ring_group_members
-- Description: Members assigned to a ring group
-- ===========================

CREATE TABLE core.ring_group_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the member entry
    ring_group_id UUID NOT NULL REFERENCES core.ring_groups(id) ON DELETE CASCADE, -- Associated ring group
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- User assigned to the ring group
    order_index INTEGER DEFAULT 1,                                        -- Order for sequential strategies
    delay INTEGER DEFAULT 0,                                             -- Optional delay before ringing
    timeout INTEGER DEFAULT 20,                                          -- Ring timeout for the user

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.ring_group_members
CREATE INDEX idx_ring_group_members_group_id ON core.ring_group_members (ring_group_id);  -- Index for joining group
CREATE INDEX idx_ring_group_members_user_id ON core.ring_group_members (user_id);          -- Index for user participation

-- ===========================
-- Table: core.pickup_groups
-- Description: Call pickup group definition
-- ===========================

CREATE TABLE core.pickup_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the pickup group
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                  -- Name of the pickup group
    description TEXT,                                                    -- Optional description
    priority INTEGER DEFAULT 100,                                        -- Priority when multiple pickups match
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether the group is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.pickup_groups
CREATE INDEX idx_pickup_groups_tenant_id ON core.pickup_groups (tenant_id);  -- For tenant isolation

-- ===========================
-- Table: core.pickup_group_settings
-- Description: Settings for pickup groups
-- ===========================

CREATE TABLE core.pickup_group_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the setting
    pickup_group_id UUID NOT NULL REFERENCES core.pickup_groups(id) ON DELETE CASCADE, -- Associated group
    category TEXT,                                                        -- Optional category
    name TEXT NOT NULL,                                                  -- Setting name
    value TEXT NOT NULL,                                                 -- Setting value
    setting_type TEXT DEFAULT 'behavior',                                -- Type of setting: behavior, security, etc.

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.pickup_group_settings
CREATE INDEX idx_pickup_group_settings_group_id ON core.pickup_group_settings (pickup_group_id); -- Join by group
CREATE INDEX idx_pickup_group_settings_name ON core.pickup_group_settings (name);                -- Filter by name

-- ===========================
-- Table: core.pickup_group_members
-- Description: Members assigned to pickup groups
-- ===========================

CREATE TABLE core.pickup_group_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier
    pickup_group_id UUID NOT NULL REFERENCES core.pickup_groups(id) ON DELETE CASCADE, -- Associated pickup group
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- SIP user assigned to the group

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.pickup_group_members
CREATE INDEX idx_pickup_group_members_group_id ON core.pickup_group_members (pickup_group_id);  -- Lookup by group
CREATE INDEX idx_pickup_group_members_user_id ON core.pickup_group_members (user_id);            -- Lookup by user

-- ===========================
-- Table: core.paging_groups
-- Description: Paging group definition
-- ===========================

CREATE TABLE core.paging_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the paging group
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                  -- Name of the paging group
    description TEXT,                                                    -- Optional description
    codec TEXT DEFAULT 'PCMU',                                           -- Paging codec
    volume INTEGER DEFAULT 5,                                            -- Paging volume
    multicast_address TEXT,                                              -- Optional multicast IP
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether group is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.paging_groups
CREATE INDEX idx_paging_groups_tenant_id ON core.paging_groups (tenant_id);  -- Lookup by tenant

-- ===========================
-- Table: core.paging_group_settings
-- Description: Settings for paging groups
-- ===========================

CREATE TABLE core.paging_group_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique setting ID
    paging_group_id UUID NOT NULL REFERENCES core.paging_groups(id) ON DELETE CASCADE, -- Related group
    category TEXT,                                                        -- Optional category
    name TEXT NOT NULL,                                                  -- Setting name
    value TEXT NOT NULL,                                                 -- Setting value
    setting_type TEXT DEFAULT 'media',                                   -- Setting type (media, behavior, etc.)

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.paging_group_settings
CREATE INDEX idx_paging_group_settings_group_id ON core.paging_group_settings (paging_group_id); -- Group relation
CREATE INDEX idx_paging_group_settings_name ON core.paging_group_settings (name);                -- Setting lookup

-- ===========================
-- Table: core.paging_group_members
-- Description: Members included in paging groups
-- ===========================

CREATE TABLE core.paging_group_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique ID
    paging_group_id UUID NOT NULL REFERENCES core.paging_groups(id) ON DELETE CASCADE, -- Associated paging group
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- SIP user assigned to the group

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.paging_group_members
CREATE INDEX idx_paging_group_members_group_id ON core.paging_group_members (paging_group_id);  -- Group join
CREATE INDEX idx_paging_group_members_user_id ON core.paging_group_members (user_id);            -- User join

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

CREATE TRIGGER trg_set_update_dialplan
BEFORE UPDATE ON core.dialplan
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_dialplan_settings
BEFORE UPDATE ON core.dialplan_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_ivr
BEFORE UPDATE ON core.ivr
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_ivr_settings
BEFORE UPDATE ON core.ivr_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_ring_groups
BEFORE UPDATE ON core.ring_groups
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_ring_group_settings
BEFORE UPDATE ON core.ring_group_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_ring_group_members
BEFORE UPDATE ON core.ring_group_members
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_pickup_groups
BEFORE UPDATE ON core.pickup_groups
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_pickup_group_settings
BEFORE UPDATE ON core.pickup_group_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_pickup_group_members
BEFORE UPDATE ON core.pickup_group_members
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_paging_groups
BEFORE UPDATE ON core.paging_groups
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_paging_group_settings
BEFORE UPDATE ON core.paging_group_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_paging_group_members
BEFORE UPDATE ON core.paging_group_members
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

