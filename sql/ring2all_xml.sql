-- File: create_ring2all.sql
-- Description: Creates and configures the ring2all database for FreeSWITCH integration.
--              Includes tables for tenants, SIP users, groups, dialplans, and SIP profiles,
--              with triggers for automatic updates and optimized indexes for performance.
-- Usage: sudo -u postgres psql -d ring2all -f ring2all.sql
-- Prerequisites: Replace $r2a_database, $r2a_user, and $r2a_password with actual values before running.

-- Create the ring2all database if it does not exist
-- Note: This assumes execution as the postgres superuser

CREATE DATABASE $r2a_database;

-- Connect to the ring2all database
\connect $r2a_database

-- Enable the uuid-ossp extension for UUID generation if not already enabled
-- This provides the uuid_generate_v4() function for unique identifiers
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pg_trgm"  WITH SCHEMA public;

-- Create the tenants table to store tenant information
CREATE TABLE public.tenants (
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
        FOREIGN KEY (parent_tenant_uuid) REFERENCES public.tenants (tenant_uuid) 
        ON DELETE SET NULL                                            -- Sets parent_tenant_uuid to NULL if parent is deleted
);

-- Index to optimize searches by tenant name
CREATE INDEX idx_tenants_name ON public.tenants (name);

-- Index to optimize searches by domain name
CREATE INDEX idx_tenants_domain_name ON public.tenants (domain_name);

-- Index to optimize searches of active tenants
CREATE INDEX idx_tenants_enabled ON public.tenants (enabled);

-- Index for faster queries ordered by creation date
CREATE INDEX idx_tenants_insert_date ON public.tenants (insert_date);

-- Create the tenant_settings table for tenant-specific configurations
CREATE TABLE public.tenant_settings (
    tenant_setting_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the setting, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    name TEXT NOT NULL,                                               -- Setting name (e.g., "max_calls")
    value TEXT NOT NULL,                                              -- Setting value (e.g., "100")
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable),
    CONSTRAINT fk_tenant_settings_tenants                             -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) 
        ON DELETE CASCADE,                                            -- Deletes settings when a tenant is removed
    CONSTRAINT unique_tenant_setting UNIQUE (tenant_uuid, name)       -- Ensures each tenant has unique setting names
);

-- Index to optimize searches by tenant UUID
CREATE INDEX idx_tenant_settings_tenant_uuid ON public.tenant_settings (tenant_uuid);

-- Index to optimize searches by setting name within a tenant
CREATE INDEX idx_tenant_settings_name ON public.tenant_settings (name);

-- Index for faster queries ordered by creation date
CREATE INDEX idx_tenant_settings_insert_date ON public.tenant_settings (insert_date);

-- Create the sip_users table for SIP user accounts
CREATE TABLE public.sip_users (
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
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE
);

-- Index to speed up queries filtering by tenant (frequent in multi-tenant environments)
CREATE INDEX idx_sip_users_tenant_uuid ON public.sip_users (tenant_uuid);

-- Index to speed up searches by extension number (common lookup)
CREATE INDEX idx_sip_users_extension ON public.sip_users (extension);

-- Index to speed up username lookups (explicit index even though it's UNIQUE)
CREATE INDEX idx_sip_users_username ON public.sip_users (username);

-- Index to optimize caller ID number lookups
CREATE INDEX idx_sip_users_caller_id_number ON public.sip_users (effective_caller_id_number);

-- Index to optimize filtering by active users
CREATE INDEX idx_sip_users_enabled ON public.sip_users (enabled);

-- Index for faster queries ordered by creation date (useful for reports)
CREATE INDEX idx_sip_users_insert_date ON public.sip_users (insert_date);

-- Create the sip_profiles table for SIP profiles configuration
CREATE TABLE public.sip_profiles (
    profile_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the SIP profile, auto-generated UUID
    tenant_uuid UUID,                                                 -- Foreign key to the associated tenant (nullable for global profiles)
    profile_name VARCHAR(255) NOT NULL,                               -- Profile name (e.g., "internal"), limited to 255 characters
    xml_data XML NOT NULL,                                            -- Stores the SIP profile configuration in XML format
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the profile is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable),
    CONSTRAINT fk_sip_profiles_tenants                                -- Foreign key linking to the tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) 
        ON DELETE SET NULL,                                           -- If tenant is deleted, set tenant_uuid to NULL
    CONSTRAINT unique_sip_profile_name_per_tenant                     -- Ensures unique profile names per tenant
        UNIQUE (tenant_uuid, profile_name)
);

-- Index to optimize searches by tenant UUID (for retrieving all profiles of a tenant)
CREATE INDEX idx_sip_profiles_tenant_uuid ON public.sip_profiles (tenant_uuid);

-- Index to optimize searches by profile name (useful when filtering by name)
CREATE INDEX idx_sip_profiles_name ON public.sip_profiles (profile_name);

-- Index to optimize searches of active SIP profiles
CREATE INDEX idx_sip_profiles_enabled ON public.sip_profiles (enabled);

-- Index for faster queries ordered by creation date (useful for logs and tracking changes)
CREATE INDEX idx_sip_profiles_insert_date ON public.sip_profiles (insert_date);

-- Create the dialplan_contexts table for FreeSWITCH dialplan contexts
CREATE TABLE public.dialplan_contexts (
    context_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the dialplan context, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    context_name VARCHAR(255) NOT NULL,                               -- Unique context name (e.g., "public"), limited to 255 characters
    description TEXT,                                                 -- Optional description of the context
    expression TEXT,                                                  -- Regular expression used in the context (without "^" and "$")
    category TEXT DEFAULT 'Uncategorized',                            -- Category for organization, defaults to "Uncategorized"
    xml_data XML NOT NULL,                                            -- Stores the dialplan context configuration in XML format
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the context is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (text, nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (text, nullable),
    CONSTRAINT fk_dialplan_contexts_tenants                           -- Foreign key linking to the tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) 
        ON DELETE CASCADE,                                            -- If tenant is deleted, remove all related contexts
    CONSTRAINT unique_context_name_per_tenant                         -- Ensures unique context names per tenant
        UNIQUE (tenant_uuid, context_name)
);

-- Index to optimize searches by tenant UUID (for retrieving all dialplan contexts of a tenant)
CREATE INDEX idx_dialplan_contexts_tenant_uuid ON public.dialplan_contexts (tenant_uuid);

-- Index to optimize searches by context name (useful when filtering by name)
CREATE INDEX idx_dialplan_contexts_name ON public.dialplan_contexts (context_name);

-- Index to optimize searches of active dialplan contexts
CREATE INDEX idx_dialplan_contexts_enabled ON public.dialplan_contexts (enabled);

-- Index for faster queries ordered by creation date (useful for logs and tracking changes)
CREATE INDEX idx_dialplan_contexts_insert_date ON public.dialplan_contexts (insert_date);

-- Full-text search index on the "expression" field to optimize regex searches
CREATE INDEX idx_dialplan_contexts_expression ON public.dialplan_contexts USING GIN (expression gin_trgm_ops);

-- Create the ivr_menus table for IVR menu configurations
CREATE TABLE public.ivr_menus (
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
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (nullable),
    CONSTRAINT fk_ivr_menus_tenants                                   -- Foreign key linking to the tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) 
        ON DELETE CASCADE,                                            -- If tenant is deleted, remove all related IVRs
    CONSTRAINT unique_ivr_name_per_tenant                             -- Ensures unique IVR names per tenant
        UNIQUE (tenant_uuid, ivr_name)
);

-- Index to optimize searches by tenant UUID (for retrieving all IVRs of a tenant)
CREATE INDEX idx_ivr_menus_tenant_uuid ON public.ivr_menus (tenant_uuid);

-- Index to optimize searches by IVR name (useful when filtering by name)
CREATE INDEX idx_ivr_menus_name ON public.ivr_menus (ivr_name);

-- Index to optimize listing active IVRs
CREATE INDEX idx_ivr_menus_insert_date ON public.ivr_menus (insert_date);

-- Create the ivr_menu_options table to store IVR menu options
CREATE TABLE public.ivr_menu_options (
    option_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),          -- Unique identifier for the IVR option, auto-generated UUID
    ivr_uuid UUID NOT NULL,                                           -- Foreign key to the associated IVR menu
    digits VARCHAR(50) NOT NULL,                                      -- Input digits (e.g., "1", "2", "9", "*")
    action VARCHAR(255) NOT NULL,                                     -- Action to execute (e.g., "transfer", "voicemail", "hangup")
    param TEXT,                                                       -- Additional parameters for the action
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (nullable),
    CONSTRAINT fk_ivr_menu_options_menus                              -- Foreign key linking to ivr_menus table
        FOREIGN KEY (ivr_uuid) REFERENCES public.ivr_menus (ivr_uuid) 
        ON DELETE CASCADE                                             -- If IVR menu is deleted, remove related options
);

-- Index to optimize searches by IVR UUID (for retrieving all options of an IVR menu)
CREATE INDEX idx_ivr_menu_options_ivr_uuid ON public.ivr_menu_options (ivr_uuid);

-- Index to optimize searches by input digits
CREATE INDEX idx_ivr_menu_options_digits ON public.ivr_menu_options (digits);

-- Index to optimize action lookups
CREATE INDEX idx_ivr_menu_options_action ON public.ivr_menu_options (action);

-- Create the ring2all role if it does not exist and configure privileges
DO $$ 
BEGIN
    -- Check if the role ($r2a_user) exists, and create it if it does not
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$r2a_user') THEN
        EXECUTE 'CREATE ROLE ' || quote_ident('$r2a_user') || ' WITH LOGIN PASSWORD ' || quote_literal('$r2a_password');
    END IF;
END $$;

-- Grant privileges to the database, schema, tables, and sequences
GRANT ALL PRIVILEGES ON DATABASE $r2a_database TO $r2a_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $r2a_user;

-- This function sets the update_date column to the current timestamp on update
CREATE OR REPLACE FUNCTION public.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.update_date = NOW(); -- Assign current timestamp to update_date
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to automatically update the update_date column on table updates
CREATE TRIGGER update_tenants_timestamp
    BEFORE UPDATE ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_tenant_settings_timestamp
    BEFORE UPDATE ON public.tenant_settings
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_sip_users_timestamp
    BEFORE UPDATE ON public.sip_users
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_sip_profiles_timestamp
    BEFORE UPDATE ON public.sip_profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_dialplan_contexts_timestamp
    BEFORE UPDATE ON public.dialplan_contexts
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_ivr_menus_timestamp
    BEFORE UPDATE ON public.ivr_menus
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_ivr_menu_options_timestamp
    BEFORE UPDATE ON public.ivr_menu_options
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

-- Set ownership of all tables to the $r2a_user role
ALTER TABLE public.tenants OWNER TO $r2a_user;
ALTER TABLE public.tenant_settings OWNER TO $r2a_user;
ALTER TABLE public.sip_users OWNER TO $r2a_user;
ALTER TABLE public.sip_profiles OWNER TO $r2a_user;
ALTER TABLE public.dialplan_contexts OWNER TO $r2a_user;
ALTER TABLE public.ivr_menus OWNER TO $r2a_user;
ALTER TABLE public.ivr_menu_options OWNER TO $r2a_user;

-- Grant EXECUTE permission on the update_timestamp function to $r2a_user
GRANT EXECUTE ON FUNCTION public.update_timestamp() TO $r2a_user;

-- Insert Demo Tenant: Default
INSERT INTO public.tenants (tenant_uuid, parent_tenant_uuid, name, domain_name, enabled, insert_user)
VALUES (
    gen_random_uuid(),  -- Generate a unique UUID for the Tenant
    NULL,               -- No parent Tenant (this is a main Tenant)
    'Default',          -- Tenant Name
    '192.168.10.22',    -- Unique domain name used in FreeSWITCH. This is updated in the installation script.
    true,               -- The Tenant is enabled
    NULL                -- No specific user assigned at this moment (can be updated later)
);

INSERT INTO public.tenant_settings (
    tenant_uuid,  -- Reference to the Tenant this setting applies to
    name,         -- Setting name (e.g., "max_extensions", "max_trunks", "call_recording")
    value         -- The actual setting value (stored as TEXT for flexibility)
) 
VALUES 
    -- Setting the maximum number of extensions for "Default" to 100
    ((SELECT tenant_uuid FROM public.tenants WHERE name = 'Default'), 
     'max_extensions', 
     '100'),

    -- Setting the maximum number of SIP trunks for "Default" to 10
    ((SELECT tenant_uuid FROM public.tenants WHERE name = 'Default'), 
     'max_trunks', 
     '10'),

    -- Enabling call recording for "Default"
    ((SELECT tenant_uuid FROM public.tenants WHERE name = 'Default'), 
     'call_recording', 
     'true');
