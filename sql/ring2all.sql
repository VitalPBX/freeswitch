-- sudo -u postgres psql -d ring2all -f create_ring2all.sql
-- Create the ring2all database as the postgres superuser
CREATE DATABASE $r2a_database;

-- Connect to the newly created ring2all database
\connect $r2a_database;

-- Enable the uuid-ossp extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define a function to automatically update the update_date column
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.update_date = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the tenants table to store tenant information
CREATE TABLE public.tenants (
    tenant_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),           -- Unique identifier for the tenant
    parent_tenant_uuid UUID,                                          -- Reference to a parent tenant (nullable)
    name TEXT NOT NULL UNIQUE,                                        -- Unique tenant name
    domain_name TEXT NOT NULL UNIQUE,                                 -- Unique domain name for FreeSWITCH
    tenant_enabled BOOLEAN DEFAULT TRUE,                              -- Flag to indicate if the tenant is active
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),               -- Timestamp of creation
    insert_user UUID,                                                 -- User who created the record
    update_date TIMESTAMP WITH TIME ZONE,                             -- Timestamp of last update
    update_user UUID,                                                 -- User who last updated the record
    CONSTRAINT fk_tenants_parent FOREIGN KEY (parent_tenant_uuid)     -- Foreign key to parent tenant
        REFERENCES public.tenants (tenant_uuid) ON DELETE SET NULL
);

-- Create the tenant_settings table for tenant-specific settings
CREATE TABLE public.tenant_settings (
    tenant_setting_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the setting
    tenant_uuid UUID NOT NULL,                                        -- Reference to the tenant
    name TEXT NOT NULL,                                               -- Setting name
    value TEXT NOT NULL,                                              -- Setting value
    CONSTRAINT fk_tenant_settings_tenants FOREIGN KEY (tenant_uuid)   -- Foreign key to tenants
        REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE,
    CONSTRAINT unique_tenant_setting UNIQUE (tenant_uuid, name)       -- Ensure unique settings per tenant
);

-- Create the sip_users table for SIP user information
CREATE TABLE public.sip_users (
    sip_user_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),        -- Unique identifier for the SIP user
    tenant_uuid UUID NOT NULL,                                        -- Reference to the tenant
    username VARCHAR(50) NOT NULL UNIQUE,                             -- Unique SIP username
    password VARCHAR(50) NOT NULL,                                    -- SIP password
    vm_password VARCHAR(50),                                          -- Voicemail password
    extension VARCHAR(20) NOT NULL,                                   -- User's extension number
    toll_allow VARCHAR(100),                                          -- Allowed toll calls
    accountcode VARCHAR(50),                                          -- Account code for billing
    user_context VARCHAR(50) DEFAULT 'default',                       -- Context for call routing
    effective_caller_id_name VARCHAR(100),                            -- Caller ID name
    effective_caller_id_number VARCHAR(50),                           -- Caller ID number
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),               -- Timestamp of creation
    insert_user UUID,                                                 -- User who created the record
    update_date TIMESTAMP WITH TIME ZONE,                             -- Timestamp of last update
    update_user UUID,                                                 -- User who last updated the record
    CONSTRAINT fk_sip_users_tenants FOREIGN KEY (tenant_uuid)         -- Foreign key to tenants
        REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE
);

-- Create the groups table for user groups
CREATE TABLE public.groups (
    group_uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),           -- Unique identifier for the group
    tenant_uuid UUID NOT NULL,                                        -- Reference to the tenant
    group_name VARCHAR(50) NOT NULL,                                  -- Name of the group
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),               -- Timestamp of creation
    insert_user UUID,                                                 -- User who created the record
    update_date TIMESTAMP WITH TIME ZONE,                             -- Timestamp of last update
    update_user UUID,                                                 -- User who last updated the record
    CONSTRAINT fk_groups_tenants FOREIGN KEY (tenant_uuid)            -- Foreign key to tenants
        REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE
);

-- Create the user_groups table to associate users with groups
CREATE TABLE public.user_groups (
    sip_user_uuid UUID REFERENCES public.sip_users(sip_user_uuid),    -- Reference to the SIP user
    group_uuid UUID REFERENCES public.groups(group_uuid),             -- Reference to the group
    tenant_uuid UUID NOT NULL,                                        -- Reference to the tenant
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),               -- Timestamp of creation
    insert_user UUID,                                                 -- User who created the record
    update_date TIMESTAMP WITH TIME ZONE,                             -- Timestamp of last update
    update_user UUID,                                                 -- User who last updated the record
    PRIMARY KEY (sip_user_uuid, group_uuid),                          -- Composite primary key
    CONSTRAINT fk_user_groups_tenants FOREIGN KEY (tenant_uuid)       -- Foreign key to tenants
        REFERENCES public.tenants (tenant_uuid) ON DELETE CASCADE
);

-- Create triggers to update the update_date column automatically
CREATE TRIGGER update_tenants_timestamp
    BEFORE UPDATE ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_tenant_settings_timestamp
    BEFORE UPDATE ON public.tenant_settings
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_sip_users_timestamp
    BEFORE UPDATE ON public.sip_users
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_groups_timestamp
    BEFORE UPDATE ON public.groups
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_user_groups_timestamp
    BEFORE UPDATE ON public.user_groups
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Create indexes to optimize query performance
CREATE INDEX idx_tenants_name ON public.tenants (name);
CREATE INDEX idx_tenants_domain_name ON public.tenants (domain_name);
CREATE INDEX idx_tenants_parent_tenant_uuid ON public.tenants (parent_tenant_uuid);
CREATE INDEX idx_tenant_settings_tenant_uuid ON public.tenant_settings (tenant_uuid);
CREATE INDEX idx_sip_users_tenant_uuid ON public.sip_users (tenant_uuid);
CREATE INDEX idx_sip_users_username ON public.sip_users (username);
CREATE INDEX idx_groups_tenant_uuid ON public.groups (tenant_uuid);
CREATE INDEX idx_groups_group_name ON public.groups (group_name);
CREATE INDEX idx_user_groups_tenant_uuid ON public.user_groups (tenant_uuid);
CREATE INDEX idx_user_groups_sip_user_uuid ON public.user_groups (sip_user_uuid);
CREATE INDEX idx_user_groups_group_uuid ON public.user_groups (group_uuid);

-- Insert a default tenant
INSERT INTO public.tenants (name, domain_name, tenant_enabled, insert_user)
VALUES ('Default', '192.168.10.21', TRUE, NULL)
ON CONFLICT (name) DO NOTHING;

-- Create the ring2all role if it doesn't exist and grant privileges
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$r2a_user') THEN
        CREATE ROLE $r2a_user WITH LOGIN PASSWORD '$r2a_password';
    END IF;
END $$;

GRANT ALL PRIVILEGES ON DATABASE $r2a_database TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $r2a_user;

-- Set the ring2all user as the owner of all tables
ALTER TABLE public.tenants OWNER TO $r2a_user;
ALTER TABLE public.tenant_settings OWNER TO $r2a_user;
ALTER TABLE public.sip_users OWNER TO $r2a_user;
ALTER TABLE public.groups OWNER TO $r2a_user;
ALTER TABLE public.user_groups OWNER TO $r2a_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO $r2a_user;

-- Create dialplan_contexts table
CREATE TABLE public.dialplan_contexts (
    context_uuid UUID PRIMARY KEY,
    tenant_uuid UUID NOT NULL,
    context_name VARCHAR(255) NOT NULL,
    description TEXT,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    insert_user VARCHAR(255),
    update_date TIMESTAMP WITH TIME ZONE,
    update_user VARCHAR(255),
    CONSTRAINT fk_dialplan_contexts_tenant_uuid FOREIGN KEY (tenant_uuid) REFERENCES public.tenants(tenant_uuid),
    CONSTRAINT unique_context_name UNIQUE (context_name)  -- Keeping unique constraint on context_name
);

-- Create dialplan_extensions table (without unique_extension_per_context)
CREATE TABLE public.dialplan_extensions (
    extension_uuid UUID PRIMARY KEY,
    context_uuid UUID NOT NULL,
    extension_name VARCHAR(255) NOT NULL,
    continue BOOLEAN DEFAULT FALSE,
    priority INTEGER DEFAULT 1,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    insert_user VARCHAR(255),
    update_date TIMESTAMP WITH TIME ZONE,
    update_user VARCHAR(255),
    CONSTRAINT fk_dialplan_extensions_context_uuid FOREIGN KEY (context_uuid) REFERENCES public.dialplan_contexts(context_uuid)
);

-- Create dialplan_conditions table
CREATE TABLE public.dialplan_conditions (
    condition_uuid UUID PRIMARY KEY,
    extension_uuid UUID NOT NULL,
    field VARCHAR(255) NOT NULL,
    expression VARCHAR(255) NOT NULL,
    break_on_match VARCHAR(50) DEFAULT 'on-false',
    condition_order INTEGER DEFAULT 1,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    insert_user VARCHAR(255),
    update_date TIMESTAMP WITH TIME ZONE,
    update_user VARCHAR(255),
    CONSTRAINT fk_dialplan_conditions_extension_uuid FOREIGN KEY (extension_uuid) REFERENCES public.dialplan_extensions(extension_uuid)
);

-- Create dialplan_actions table
CREATE TABLE public.dialplan_actions (
    action_uuid UUID PRIMARY KEY,
    condition_uuid UUID NOT NULL,
    action_type VARCHAR(50) NOT NULL,
    application VARCHAR(255) NOT NULL,
    data TEXT,
    action_order INTEGER DEFAULT 1,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    insert_user VARCHAR(255),
    update_date TIMESTAMP WITH TIME ZONE,
    update_user VARCHAR(255),
    CONSTRAINT fk_dialplan_actions_condition_uuid FOREIGN KEY (condition_uuid) REFERENCES public.dialplan_conditions(condition_uuid)
);

-- Optional: Add indexes for better performance
CREATE INDEX idx_dialplan_extensions_context_uuid ON public.dialplan_extensions(context_uuid);
CREATE INDEX idx_dialplan_conditions_extension_uuid ON public.dialplan_conditions(extension_uuid);
CREATE INDEX idx_dialplan_actions_condition_uuid ON public.dialplan_actions(condition_uuid);

-- Trigger to update update_date
CREATE TRIGGER trig_update_dialplan_actions
BEFORE UPDATE ON public.dialplan_actions
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Grant privileges to ring2all
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dialplan_actions TO $r2a_user;

-- Grant EXECUTE on the trigger function to ring2all
GRANT EXECUTE ON FUNCTION update_timestamp() TO $r2a_user;;

-- Table to store SIP profiles (without settings)
CREATE TABLE public.sip_profiles (
    profile_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_uuid UUID REFERENCES public.tenants(tenant_uuid),
    profile_name VARCHAR(255) NOT NULL,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    insert_user UUID,
    update_date TIMESTAMP WITH TIME ZONE,
    update_user UUID,
    CONSTRAINT unique_sip_profile UNIQUE (tenant_uuid, profile_name)
);

-- Index to improve queries by tenant_uuid and profile_name
CREATE INDEX idx_sip_profiles_tenant_uuid_profile_name ON public.sip_profiles (tenant_uuid, profile_name);

-- Trigger to auto-update update_date on sip_profiles
CREATE TRIGGER trigger_update_sip_profiles
BEFORE UPDATE ON public.sip_profiles
FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

-- New table to store individual settings for SIP profiles
CREATE TABLE public.sip_profile_settings (
    setting_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_uuid UUID REFERENCES public.sip_profiles(profile_uuid) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    insert_user UUID,
    CONSTRAINT unique_sip_profile_setting UNIQUE (profile_uuid, name)
);

-- Index to improve queries by profile_uuid and name
CREATE INDEX idx_sip_profile_settings_profile_uuid_name ON public.sip_profile_settings (profile_uuid, name);

-- Table to store gateways associated with SIP profiles
CREATE TABLE public.sip_profile_gateways (
    gateway_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_uuid UUID REFERENCES public.sip_profiles(profile_uuid) ON DELETE CASCADE,
    gateway_name VARCHAR(255) NOT NULL,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    insert_user UUID,
    CONSTRAINT unique_sip_profile_gateway UNIQUE (profile_uuid, gateway_name)
);

-- Index to improve queries by profile_uuid and gateway_name
CREATE INDEX idx_sip_profile_gateways_profile_uuid_gateway_name ON public.sip_profile_gateways (profile_uuid, gateway_name);

-- New table to store individual settings for gateways
CREATE TABLE public.sip_profile_gateway_settings (
    setting_uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway_uuid UUID REFERENCES public.sip_profile_gateways(gateway_uuid) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    insert_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    insert_user UUID,
    CONSTRAINT unique_sip_profile_gateway_setting UNIQUE (gateway_uuid, name)
);

-- Index to improve queries by gateway_uuid and name
CREATE INDEX idx_sip_profile_gateway_settings_gateway_uuid_name ON public.sip_profile_gateway_settings (gateway_uuid, name);

-- Set the ring2all user as the owner of all tables
ALTER TABLE public.dialplan_contexts OWNER TO $r2a_user;
ALTER TABLE public.dialplan_extensions OWNER TO $r2a_user;
ALTER TABLE public.dialplan_conditions OWNER TO $r2a_user;
ALTER TABLE public.dialplan_actions OWNER TO $r2a_user;
ALTER TABLE public.sip_profiles OWNER TO $r2a_user;
ALTER TABLE public.sip_profile_settings OWNER TO $r2a_user;
ALTER TABLE public.sip_profile_gateways OWNER TO $r2a_user;
ALTER TABLE public.sip_profile_gateway_settings OWNER TO $r2a_user;
