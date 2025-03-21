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

-- Create the sip_users table for SIP user accounts
CREATE TABLE core.sip_users (
    sip_user_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),        -- Unique identifier for the SIP user, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    username VARCHAR(50) NOT NULL UNIQUE,                             -- Unique SIP username (e.g., "user123"), limited to 50 characters
    password VARCHAR(50) NOT NULL,                                    -- SIP authentication password, limited to 50 characters
    vm_password VARCHAR(50),                                          -- Voicemail password (nullable), limited to 50 characters
    extension VARCHAR(20) NOT NULL,                                   -- Extension number (e.g., "1001"), limited to 20 characters
    toll_allow VARCHAR(100),                                          -- Allowed toll call types (e.g., "international"), nullable
    accountcode VARCHAR(50),                                          -- Account code for billing (nullable), limited to 50 characters
    user_context VARCHAR(50) NOT NULL DEFAULT 'default',              -- FreeSWITCH context for call routing, defaults to 'default'
    effective_caller_id_name VARCHAR(100),                            -- Caller ID name (e.g., "John Doe"), nullable
    effective_caller_id_number VARCHAR(50),                           -- Caller ID number (e.g., "1234567890"), nullable
    xml_data XML NOT NULL,                                            -- Stores SIP user configuration in XML format
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the user is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_sip_users_tenants                                   -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES tenants (tenant_uuid) ON DELETE CASCADE
);

-- Indexes for sip_users
CREATE INDEX idx_sip_users_tenant_uuid ON core.sip_users (tenant_uuid);
CREATE INDEX idx_sip_users_extension ON core.sip_users (extension);
CREATE INDEX idx_sip_users_username ON core.sip_users (username);
CREATE INDEX idx_sip_users_caller_id_number ON core.sip_users (effective_caller_id_number);
CREATE INDEX idx_sip_users_enabled ON core.sip_users (enabled);
CREATE INDEX idx_sip_users_insert_date ON core.sip_users (insert_date);

-- Create the sip_profiles table for SIP profiles configuration
CREATE TABLE core.sip_profiles (
    profile_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the SIP profile, auto-generated UUID
    profile_name VARCHAR(255) NOT NULL UNIQUE,                        -- Unique profile name (e.g., "internal"), limited to 255 characters
    xml_data XML NOT NULL,                                            -- Stores the SIP profile configuration in XML format
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the profile is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID                                                  -- UUID of the user who last updated the record (nullable)
);

-- Indexes for sip_profiles
CREATE UNIQUE INDEX idx_sip_profiles_name ON core.sip_profiles (profile_name);
CREATE INDEX idx_sip_profiles_enabled ON core.sip_profiles (enabled);
CREATE INDEX idx_sip_profiles_insert_date ON core.sip_profiles (insert_date);

-- Create the dialplan table for FreeSWITCH dialplan contexts
CREATE TABLE core.dialplan (
    context_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the dialplan entry, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    context_name VARCHAR(255) NOT NULL,                               -- Context name (e.g., "public"), limited to 255 characters
    name TEXT,                                                        -- Name of dialplan
    description TEXT,                                                 -- Optional description of the entry
    expression TEXT,                                                  -- Regular expression used in the extension (without "^" and "$")
    category TEXT DEFAULT 'Uncategorized',                            -- Category for organization, defaults to "Uncategorized"
    xml_data XML NOT NULL,                                            -- Stores the extension configuration in XML format
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the entry is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (text, nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (text, nullable)
    CONSTRAINT fk_dialplan_tenants                                    -- Foreign key linking to the tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES tenants (tenant_uuid) 
        ON DELETE CASCADE                                             -- If tenant is deleted, remove all related entries
);

-- Indexes for dialplan
CREATE INDEX idx_dialplan_tenant_uuid ON core.dialplan (tenant_uuid);
CREATE INDEX idx_dialplan_name ON core.dialplan (context_name);
CREATE INDEX idx_dialplan_enabled ON core.dialplan (enabled);
CREATE INDEX idx_dialplan_insert_date ON core.dialplan (insert_date);
CREATE INDEX idx_dialplan_expression ON core.dialplan USING GIN (expression gin_trgm_ops);

-- Create the ivr_menus table for IVR menu configurations
CREATE TABLE core.ivr_menus (
    ivr_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),             -- Unique identifier for the IVR menu, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    ivr_name VARCHAR(255) NOT NULL,                                   -- Unique IVR menu name (e.g., "Main Menu")
    greet_long VARCHAR(255),                                          -- Path to the long greeting audio file
    greet_short VARCHAR(255),                                         -- Path to the short greeting audio file
    invalid_sound VARCHAR(255),                                       -- Path to the invalid input audio file
    exit_sound VARCHAR(255),                                          -- Path to the exit audio file
    timeout INTEGER NOT NULL DEFAULT 10000,                           -- Timeout in milliseconds before IVR fallback
    max_failures INTEGER NOT NULL DEFAULT 3,                          -- Maximum number of invalid attempts before fallback
    max_timeouts INTEGER NOT NULL DEFAULT 3,                          -- Maximum number of timeouts before fallback
    xml_data XML NOT NULL,                                            -- Stores the dialplan context configuration in XML format
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the context is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (nullable),
    CONSTRAINT fk_ivr_menus_tenants                                   -- Foreign key linking to the tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES tenants (tenant_uuid) 
        ON DELETE CASCADE,                                            -- If tenant is deleted, remove all related IVRs
    CONSTRAINT unique_ivr_name_per_tenant                             -- Ensures unique IVR names per tenant
        UNIQUE (tenant_uuid, ivr_name)
);

-- Indexes for ivr_menus
CREATE INDEX idx_ivr_menus_tenant_uuid ON core.ivr_menus (tenant_uuid);
CREATE INDEX idx_ivr_menus_name ON core.ivr_menus (ivr_name);
CREATE INDEX idx_ivr_menus_insert_date ON core.ivr_menus (insert_date);

-- Create the ivr_menu_options table to store IVR menu options
CREATE TABLE core.ivr_menu_options (
    option_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),          -- Unique identifier for the IVR option, auto-generated UUID
    ivr_uuid UUID NOT NULL,                                           -- Foreign key to the associated IVR menu
    digits VARCHAR(50) NOT NULL,                                      -- Input digits (e.g., "1", "2", "9", "*")
    action VARCHAR(255) NOT NULL,                                     -- Action to execute (e.g., "transfer", "voicemail", "hangup")
    param TEXT,                                                       -- Additional parameters for the action
    xml_data XML,                                                     -- Stores the dialplan context configuration in XML format
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the context is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (nullable),
    CONSTRAINT fk_ivr_menu_options_menus                              -- Foreign key linking to ivr_menus table
        FOREIGN KEY (ivr_uuid) REFERENCES core.ivr_menus (ivr_uuid) 
        ON DELETE CASCADE                                             -- If IVR menu is deleted, remove related options
);

-- Indexes for ivr_menu_options
CREATE INDEX idx_ivr_menu_options_ivr_uuid ON core.ivr_menu_options (ivr_uuid);
CREATE INDEX idx_ivr_menu_options_digits ON core.ivr_menu_options (digits);
CREATE INDEX idx_ivr_menu_options_action ON core.ivr_menu_options (action);


-- Create the user groups table
CREATE TABLE core.directory_groups (
    group_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),           -- Unique identifier for the group
    tenant_uuid UUID NOT NULL,                                        -- Reference to the associated tenant
    group_name VARCHAR(255) NOT NULL,                                 -- Name of the group (e.g., "sales", "support")
    description TEXT,                                                 -- Optional description of the group
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp
    insert_user UUID,                                                 -- UUID of the user who created the group
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp
    update_user UUID,                                                 -- UUID of the user who last updated the group
    CONSTRAINT fk_user_groups_tenants                                 -- Foreign key constraint to tenants
        FOREIGN KEY (tenant_uuid) REFERENCES tenants (tenant_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_group_name_per_tenant                           -- Ensure unique group names per tenant
        UNIQUE (tenant_uuid, group_name)
);

-- Indexes for user_groups
CREATE INDEX idx_directory_groups_tenant_uuid ON core.directory_groups (tenant_uuid);
CREATE INDEX idx_directory_groups_group_name ON core.directory_groups (group_name);
CREATE INDEX idx_directory_groups_insert_date ON core.directory_groups (insert_date);

-- Create the group_members table to associate SIP users to groups
CREATE TABLE core.directory_group_members (
    member_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),          -- Unique identifier for the membership
    group_uuid UUID NOT NULL,                                         -- Reference to the user group
    sip_user_uuid UUID NOT NULL,                                      -- Reference to the SIP user
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp
    insert_user UUID,                                                 -- UUID of the user who created the entry
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp
    update_user UUID,                                                 -- UUID of the user who last updated the entry
    CONSTRAINT fk_group_members_group                                 -- Foreign key to groups
        FOREIGN KEY (group_uuid) REFERENCES core.directory_groups (group_uuid) ON DELETE CASCADE,
    CONSTRAINT fk_group_members_user                                  -- Foreign key to users
        FOREIGN KEY (sip_user_uuid) REFERENCES core.sip_users (sip_user_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_user_per_group                                  -- Avoid duplicate user membership in the same group
        UNIQUE (group_uuid, sip_user_uuid)
);

-- Indexes for group_members
CREATE INDEX idx_directory_group_members_group_uuid ON core.directory_group_members (group_uuid);
CREATE INDEX idx_directory_group_members_sip_user_uuid ON core.directory_group_members (sip_user_uuid);

-- === END FULL SCHEMA DEFINITION ===

-- Create audit trigger function to auto-update the "update_date" column
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.update_date = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for auto-updating update_date
CREATE TRIGGER update_tenants_timestamp
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_tenant_settings_timestamp
    BEFORE UPDATE ON tenant_settings
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_core_sip_users_timestamp
    BEFORE UPDATE ON core.sip_users
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_core_sip_profiles_timestamp
    BEFORE UPDATE ON core.sip_profiles
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_core_dialplan_timestamp
    BEFORE UPDATE ON core.dialplan
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_core_ivr_menus_timestamp
    BEFORE UPDATE ON core.ivr_menus
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_core_ivr_menu_options_timestamp
    BEFORE UPDATE ON core.ivr_menu_options
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_core_directory_groups_timestamp
    BEFORE UPDATE ON core.directory_groups
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_core_directory_group_members_timestamp
    BEFORE UPDATE ON core.directory_group_members
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Set ownership of tables to the application role
ALTER TABLE tenants OWNER TO $r2a_user;
ALTER TABLE tenant_settings OWNER TO $r2a_user;
ALTER TABLE core.sip_users OWNER TO $r2a_user;
ALTER TABLE core.sip_profiles OWNER TO $r2a_user;
ALTER TABLE core.dialplan OWNER TO $r2a_user;
ALTER TABLE core.ivr_menus OWNER TO $r2a_user;
ALTER TABLE core.ivr_menu_options OWNER TO $r2a_user;

-- Grant EXECUTE on function to the application role
GRANT EXECUTE ON FUNCTION update_timestamp() TO $r2a_user;

-- Insert demo tenant for testing and default use
INSERT INTO tenants (tenant_uuid, parent_tenant_uuid, name, domain_name, enabled, insert_user)
VALUES (
    gen_random_uuid(),                  -- Generate a unique UUID for the tenant
    NULL,                               -- No parent tenant
    'Default',                          -- Tenant name
    '192.168.10.22',                    -- Domain name for FreeSWITCH (can be replaced in install)
    TRUE,                               -- Tenant is enabled
    NULL                                -- Inserted by system
);

-- Insert default tenant settings
INSERT INTO tenant_settings (tenant_uuid, name, value)
VALUES
((SELECT tenant_uuid FROM tenants WHERE name = 'Default'), 'max_extensions', '100'),
((SELECT tenant_uuid FROM tenants WHERE name = 'Default'), 'max_trunks', '10'),
((SELECT tenant_uuid FROM tenants WHERE name = 'Default'), 'call_recording', 'true');
