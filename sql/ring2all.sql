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
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_tenants_parent FOREIGN KEY (parent_tenant_uuid)     -- Foreign key to support tenant hierarchy
        REFERENCES public.tenants (tenant_uuid) ON DELETE SET NULL    -- Sets parent_tenant_uuid to NULL if parent is deleted
);

-- Create the tenant_settings table for tenant-specific configurations
CREATE TABLE public.tenant_settings (
    tenant_setting_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the setting, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    name TEXT NOT NULL,                                               -- Setting name (e.g., "max_calls")
    value TEXT NOT NULL,                                              -- Setting value (e.g., "100")
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_tenant_settings_tenants                             -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_tenant_setting UNIQUE (tenant_uuid, name)       -- Ensures each tenant has unique setting names
);

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
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the user is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_sip_users_tenants                                   -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE
);

-- Create the groups table for user group definitions
CREATE TABLE public.groups (
    group_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),           -- Unique identifier for the group, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    group_name VARCHAR(50) NOT NULL,                                  -- Group name (e.g., "admins"), limited to 50 characters
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_groups_tenants                                      -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_group_name_per_tenant UNIQUE (tenant_uuid, group_name) -- Ensures unique group names per tenant
);

-- Create the user_groups table to associate SIP users with groups
CREATE TABLE public.user_groups (
    sip_user_uuid UUID NOT NULL,                                      -- Foreign key to the SIP user
    group_uuid UUID NOT NULL,                                         -- Foreign key to the group
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    PRIMARY KEY (sip_user_uuid, group_uuid),                          -- Composite primary key to ensure unique user-group pairs
    CONSTRAINT fk_user_groups_sip_users                               -- Foreign key to sip_users table
        FOREIGN KEY (sip_user_uuid) REFERENCES public.sip_users (sip_user_uuid) ON DELETE CASCADE,
    CONSTRAINT fk_user_groups_groups                                  -- Foreign key to groups table
        FOREIGN KEY (group_uuid) REFERENCES public.groups (group_uuid) ON DELETE CASCADE,
    CONSTRAINT fk_user_groups_tenants                                 -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE
);

-- Create the dialplan_contexts table for FreeSWITCH dialplan contexts
CREATE TABLE public.dialplan_contexts (
    context_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the context, auto-generated UUID
    tenant_uuid UUID NOT NULL,                                        -- Foreign key to the associated tenant
    context_name VARCHAR(255) NOT NULL,                               -- Context name (e.g., "public"), limited to 255 characters
    description TEXT,                                                 -- Optional description of the context
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the context is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (text, nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (text, nullable)
    CONSTRAINT fk_dialplan_contexts_tenants                           -- Foreign key to tenants table
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_context_name_per_tenant UNIQUE (tenant_uuid, context_name) -- Ensures unique context names per tenant
);

-- Create the dialplan_extensions table for dialplan extensions within contexts
CREATE TABLE public.dialplan_extensions (
    extension_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),       -- Unique identifier for the extension, auto-generated UUID
    context_uuid UUID NOT NULL,                                       -- Foreign key to the associated context
    extension_name VARCHAR(255) NOT NULL,                             -- Extension name (e.g., "incoming"), limited to 255 characters
    continue_on BOOLEAN NOT NULL DEFAULT FALSE,                       -- Whether to continue processing after this extension
    priority INTEGER NOT NULL DEFAULT 1 CHECK (priority >= 1),        -- Priority order (1 or higher), higher executes first
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (text, nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (text, nullable)
    CONSTRAINT fk_dialplan_extensions_contexts                        -- Foreign key to dialplan_contexts table
        FOREIGN KEY (context_uuid) REFERENCES public.dialplan_contexts (context_uuid) ON DELETE CASCADE
);

-- Create the dialplan_conditions table for conditions within extensions
CREATE TABLE public.dialplan_conditions (
    condition_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),       -- Unique identifier for the condition, auto-generated UUID
    extension_uuid UUID NOT NULL,                                     -- Foreign key to the associated extension
    field VARCHAR(255) NOT NULL,                                      -- Field to evaluate (e.g., "destination_number")
    expression VARCHAR(255) NOT NULL,                                 -- Regex or value to match (e.g., "^1234$")
    break_on_match VARCHAR(50) NOT NULL DEFAULT 'on-false',           -- Break behavior (e.g., 'on-true', 'on-false', 'never')
    condition_order INTEGER NOT NULL DEFAULT 1 CHECK (condition_order >= 1), -- Order of evaluation (1 or higher)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (text, nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (text, nullable)
    CONSTRAINT fk_dialplan_conditions_extensions                      -- Foreign key to dialplan_extensions table
        FOREIGN KEY (extension_uuid) REFERENCES public.dialplan_extensions (extension_uuid) ON DELETE CASCADE,
    CONSTRAINT valid_break_on_match CHECK (break_on_match IN ('on-true', 'on-false', 'never')) -- Restrict valid values
);

-- Create the dialplan_actions table for actions within conditions
CREATE TABLE public.dialplan_actions (
    action_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),          -- Unique identifier for the action, auto-generated UUID
    condition_uuid UUID NOT NULL,                                     -- Foreign key to the associated condition
    action_type VARCHAR(50) NOT NULL DEFAULT 'action',                -- Type of action (e.g., 'action', 'anti-action'), defaults to 'action'
    application VARCHAR(255) NOT NULL,                                -- FreeSWITCH application (e.g., "bridge")
    data TEXT,                                                        -- Application data (e.g., "user/1001"), nullable
    action_order INTEGER NOT NULL DEFAULT 1 CHECK (action_order >= 1),-- Order of execution (1 or higher)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user VARCHAR(255),                                         -- User who created the record (text, nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user VARCHAR(255),                                         -- User who last updated the record (text, nullable)
    CONSTRAINT fk_dialplan_actions_conditions                         -- Foreign key to dialplan_conditions table
        FOREIGN KEY (condition_uuid) REFERENCES public.dialplan_conditions (condition_uuid) ON DELETE CASCADE,
    CONSTRAINT valid_action_type CHECK (action_type IN ('action', 'anti-action')) -- Restrict valid action types
);

-- Create the sip_profiles table for SIP profiles configuration
CREATE TABLE public.sip_profiles (
    profile_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the SIP profile, auto-generated UUID
    tenant_uuid UUID,                                                 -- Foreign key to the associated tenant (nullable for global profiles)
    profile_name VARCHAR(255) NOT NULL,                               -- Profile name (e.g., "internal"), limited to 255 characters
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the profile is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_sip_profiles_tenants                                -- Foreign key to tenants table (nullable)
        FOREIGN KEY (tenant_uuid) REFERENCES public.tenants (tenant_uuid) ON DELETE SET NULL,
    CONSTRAINT unique_sip_profile_name_per_tenant UNIQUE (tenant_uuid, profile_name) -- Ensures unique profile names per tenant
);

-- Create the sip_profile_settings table for individual SIP profile settings
CREATE TABLE public.sip_profile_settings (
    setting_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the setting, auto-generated UUID
    profile_uuid UUID NOT NULL,                                       -- Foreign key to the associated SIP profile
    name VARCHAR(255) NOT NULL,                                       -- Setting name (e.g., "sip-port")
    value TEXT NOT NULL,                                              -- Setting value (e.g., "5080")
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_sip_profile_settings_profiles                       -- Foreign key to sip_profiles table
        FOREIGN KEY (profile_uuid) REFERENCES public.sip_profiles (profile_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_sip_profile_setting UNIQUE (profile_uuid, name) -- Ensures unique settings per profile
);

-- Create the sip_profile_gateways table for gateways associated with SIP profiles
CREATE TABLE public.sip_profile_gateways (
    gateway_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the gateway, auto-generated UUID
    profile_uuid UUID NOT NULL,                                       -- Foreign key to the associated SIP profile
    gateway_name VARCHAR(255) NOT NULL,                               -- Gateway name (e.g., "provider1"), limited to 255 characters
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the gateway is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_sip_profile_gateways_profiles                       -- Foreign key to sip_profiles table
        FOREIGN KEY (profile_uuid) REFERENCES public.sip_profiles (profile_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_sip_profile_gateway UNIQUE (profile_uuid, gateway_name) -- Ensures unique gateway names per profile
);

-- Create the sip_profile_gateway_settings table for individual gateway settings
CREATE TABLE public.sip_profile_gateway_settings (
    setting_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),         -- Unique identifier for the setting, auto-generated UUID
    gateway_uuid UUID NOT NULL,                                       -- Foreign key to the associated gateway
    name VARCHAR(255) NOT NULL,                                       -- Setting name (e.g., "username")
    value TEXT NOT NULL,                                              -- Setting value (e.g., "user123")
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable)
    CONSTRAINT fk_sip_profile_gateway_settings_gateways               -- Foreign key to sip_profile_gateways table
        FOREIGN KEY (gateway_uuid) REFERENCES public.sip_profile_gateways (gateway_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_sip_profile_gateway_setting UNIQUE (gateway_uuid, name) -- Ensures unique settings per gateway
);

-- Define a function to automatically update the update_date column on row updates
-- This function sets the update_date to the current timestamp with timezone
CREATE OR REPLACE FUNCTION public.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.update_date = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to automatically update the update_date column for all tables
CREATE TRIGGER update_tenants_timestamp
    BEFORE UPDATE ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_tenant_settings_timestamp
    BEFORE UPDATE ON public.tenant_settings
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_sip_users_timestamp
    BEFORE UPDATE ON public.sip_users
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_groups_timestamp
    BEFORE UPDATE ON public.groups
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_user_groups_timestamp
    BEFORE UPDATE ON public.user_groups
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_dialplan_contexts_timestamp
    BEFORE UPDATE ON public.dialplan_contexts
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_dialplan_extensions_timestamp
    BEFORE UPDATE ON public.dialplan_extensions
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_dialplan_conditions_timestamp
    BEFORE UPDATE ON public.dialplan_conditions
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_dialplan_actions_timestamp
    BEFORE UPDATE ON public.dialplan_actions
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_sip_profiles_timestamp
    BEFORE UPDATE ON public.sip_profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_sip_profile_settings_timestamp
    BEFORE UPDATE ON public.sip_profile_settings
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_sip_profile_gateways_timestamp
    BEFORE UPDATE ON public.sip_profile_gateways
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_sip_profile_gateway_settings_timestamp
    BEFORE UPDATE ON public.sip_profile_gateway_settings
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

-- Create indexes to optimize query performance and enforce referential integrity
CREATE INDEX idx_tenants_name ON public.tenants (name);                     -- Index for tenant name lookups
CREATE INDEX idx_tenants_domain_name ON public.tenants (domain_name);       -- Index for domain name lookups
CREATE INDEX idx_tenants_parent_tenant_uuid ON public.tenants (parent_tenant_uuid); -- Index for parent tenant relationships
CREATE INDEX idx_tenant_settings_tenant_uuid ON public.tenant_settings (tenant_uuid); -- Index for tenant settings lookups
CREATE INDEX idx_sip_users_tenant_uuid ON public.sip_users (tenant_uuid);   -- Index for SIP user lookups by tenant
CREATE INDEX idx_sip_users_username ON public.sip_users (username);         -- Index for SIP username lookups
CREATE INDEX idx_groups_tenant_uuid ON public.groups (tenant_uuid);         -- Index for group lookups by tenant
CREATE INDEX idx_user_groups_tenant_uuid ON public.user_groups (tenant_uuid); -- Index for user-group lookups by tenant
CREATE INDEX idx_user_groups_sip_user_uuid ON public.user_groups (sip_user_uuid); -- Index for user-group lookups by user
CREATE INDEX idx_user_groups_group_uuid ON public.user_groups (group_uuid); -- Index for user-group lookups by group
CREATE INDEX idx_dialplan_contexts_tenant_uuid ON public.dialplan_contexts (tenant_uuid); -- Index for context lookups by tenant
CREATE INDEX idx_dialplan_extensions_context_uuid ON public.dialplan_extensions (context_uuid); -- Index for extension lookups by context
CREATE INDEX idx_dialplan_conditions_extension_uuid ON public.dialplan_conditions (extension_uuid); -- Index for condition lookups by extension
CREATE INDEX idx_dialplan_actions_condition_uuid ON public.dialplan_actions (condition_uuid); -- Index for action lookups by condition
CREATE INDEX idx_sip_profiles_tenant_uuid ON public.sip_profiles (tenant_uuid); -- Index for SIP profile lookups by tenant
CREATE INDEX idx_sip_profile_settings_profile_uuid ON public.sip_profile_settings (profile_uuid); -- Index for setting lookups by profile
CREATE INDEX idx_sip_profile_gateways_profile_uuid ON public.sip_profile_gateways (profile_uuid); -- Index for gateway lookups by profile
CREATE INDEX idx_sip_profile_gateway_settings_gateway_uuid ON public.sip_profile_gateway_settings (gateway_uuid); -- Index for gateway setting lookups

-- Insert a default tenant if it does not already exist
INSERT INTO public.tenants (name, domain_name, enabled, insert_user)
VALUES ('Default', '192.168.10.21', TRUE, NULL)
ON CONFLICT (name) DO NOTHING;

-- Create the ring2all role if it does not exist and configure privileges
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$r2a_user') THEN
        EXECUTE 'CREATE ROLE ' || quote_ident('$r2a_user') || ' WITH LOGIN PASSWORD ' || quote_literal('$r2a_password');
    END IF;
END $$;

-- Grant full privileges to the ring2all user on the database and schema
GRANT ALL PRIVILEGES ON DATABASE $r2a_database TO $r2a_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $r2a_user;
GRANT EXECUTE ON FUNCTION public.update_timestamp() TO $r2a_user;

-- Set ownership of all tables to the ring2all user
ALTER TABLE public.tenants OWNER TO $r2a_user;
ALTER TABLE public.tenant_settings OWNER TO $r2a_user;
ALTER TABLE public.sip_users OWNER TO $r2a_user;
ALTER TABLE public.groups OWNER TO $r2a_user;
ALTER TABLE public.user_groups OWNER TO $r2a_user;
ALTER TABLE public.dialplan_contexts OWNER TO $r2a_user;
ALTER TABLE public.dialplan_extensions OWNER TO $r2a_user;
ALTER TABLE public.dialplan_conditions OWNER TO $r2a_user;
ALTER TABLE public.dialplan_actions OWNER TO $r2a_user;
ALTER TABLE public.sip_profiles OWNER TO $r2a_user;
ALTER TABLE public.sip_profile_settings OWNER TO $r2a_user;
ALTER TABLE public.sip_profile_gateways OWNER TO $r2a_user;
ALTER TABLE public.sip_profile_gateway_settings OWNER TO $r2a_user;

-- Grant EXECUTE on the trigger function to ring2all
GRANT EXECUTE ON FUNCTION update_timestamp() TO $r2a_user;;
