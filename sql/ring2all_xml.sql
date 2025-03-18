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
CREATE TABLE public.sip_extensions (
    extension_uuid uuid NOT NULL,
    tenant_uuid uuid NOT NULL,
    extension text,
    number_alias text,
    password text,
    accountcode text,
    effective_caller_id_name text,
    effective_caller_id_number text,
    outbound_caller_id_name text,
    outbound_caller_id_number text,
    emergency_caller_id_name text,
    emergency_caller_id_number text,
    directory_first_name text,
    directory_last_name text,
    directory_visible text,
    directory_exten_visible text,
    max_registrations text,
    limit_max text,
    limit_destination text,
    missed_call_app text,
    missed_call_data text,
    user_context text,
    toll_allow text,
    call_timeout numeric,
    call_group text,
    call_screen_enabled text,
    user_record text,
    hold_music text,
    auth_acl text,
    cidr text,
    sip_force_contact text,
    nibble_account text,
    sip_force_expires numeric,
    mwi_account text,
    sip_bypass_media text,
    unique_id numeric,
    dial_string text,
    dial_user text,
    dial_domain text,
    do_not_disturb text,
    forward_all_destination text,
    forward_all_enabled text,
    forward_busy_destination text,
    forward_busy_enabled text,
    forward_no_answer_destination text,
    forward_no_answer_enabled text,
    forward_user_not_registered_destination text,
    forward_user_not_registered_enabled text,
    follow_me_uuid uuid,
    follow_me_enabled text,
    follow_me_destinations text,
    extension_language text,
    extension_dialect text,
    extension_voice text,
    extension_type text,
    enabled text,
    description text,
    absolute_codec_string text,
    force_ping text,
    xml_config XML NOT NULL, 
    insert_date timestamp with time zone DEFAULT now(),
    insert_user uuid,
    update_date timestamp with time zone DEFAULT now(),
    update_user uuid
);

CREATE TABLE public.voicemails (
    voicemail_uuid uuid NOT NULL,
    tenant_uuid uuid NOT NULL,
    voicemail_id text,
    voicemail_password text,
    greeting_id numeric,
    voicemail_alternate_greet_id numeric,
    voicemail_recording_instructions text,
    voicemail_recording_options text,
    voicemail_mail_to text,
    voicemail_sms_to text,
    voicemail_transcription_enabled text,
    voicemail_attach_file text,
    voicemail_file text,
    voicemail_local_after_email text,
    voicemail_local_after_forward text,
    voicemail_enabled text,
    voicemail_description text,
    voicemail_name_base64 text,
    voicemail_tutorial text,
    insert_date timestamp with time zone DEFAULT now(),
    insert_user uuid,
    update_date timestamp with time zone DEFAULT now(),
    update_user uuid
);

CREATE TABLE public.sip_profiles (
    profile_uuid UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    profile_name TEXT UNIQUE NOT NULL,
    tenant_uuid UUID NOT NULL,
    xml_config XML NOT NULL,
    insert_date TIMESTAMP DEFAULT NOW(),
    insert_user UUID,
    update_date TIMESTAMP DEFAULT NOW(),
    update_user UUID
);

CREATE TABLE public.dialplan (
    rule_uuid UUID PRIMARY KEY,
    tenant_uuid UUID NOT NULL,
    context TEXT NOT NULL,
    name TEXT NOT NULL,
    expression TEXT,
    category TEXT DEFAULT 'Uncategorized',
    xml_config XML NOT NULL,
    insert_date TIMESTAMP DEFAULT NOW(),
    insert_user UUID,
    update_date TIMESTAMP DEFAULT NOW(),
    update_user UUID,
    enabled BOOLEAN DEFAULT TRUE,
    CONSTRAINT unique_dialplan_rule UNIQUE (name, context)
);

-- Create the ring2all role if it does not exist and configure privileges
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$r2a_user') THEN
        EXECUTE 'CREATE ROLE ' || quote_ident('$r2a_user') || ' WITH LOGIN PASSWORD ' || quote_literal('$r2a_password');
    END IF;
END $$;

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

-- Create triggers to automatically update the update_date column for all tables
CREATE TRIGGER update_sip_extensions_timestamp
    BEFORE UPDATE ON public.sip_extensions
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_voicemails_timestamp
    BEFORE UPDATE ON public.voicemails
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER update_dialplan_timestamp
    BEFORE UPDATE ON public.dialplan
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE INDEX idx_tenants_domain_name ON public.tenants (domain_name);
CREATE INDEX idx_tenants_name ON public.tenants (name);
CREATE INDEX idx_tenants_enabled ON public.tenants (enabled);
CREATE INDEX idx_tenants_parent_uuid ON public.tenants (parent_tenant_uuid);

CREATE INDEX idx_sip_users_tenant_uuid ON public.sip_extensions (tenant_uuid); 
CREATE INDEX idx_sip_users_extension ON public.sip_extensions (extension);

GRANT ALL PRIVILEGES ON DATABASE $r2a_database TO $r2a_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $r2a_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $r2a_user;
GRANT EXECUTE ON FUNCTION public.update_timestamp() TO $r2a_user;

-- Set ownership of all tables to the ring2all user
ALTER TABLE public.tenants OWNER TO $r2a_user;
ALTER TABLE public.tenant_settings OWNER TO $r2a_user;
ALTER TABLE public.sip_extensions OWNER TO $r2a_user;
ALTER TABLE public.sip_profiles OWNER TO $r2a_user;
ALTER TABLE public.dialplan OWNER TO $r2a_user;

-- Grant EXECUTE on the trigger function to ring2all
GRANT EXECUTE ON FUNCTION update_timestamp() TO $r2a_user;

INSERT INTO public.tenants (tenant_uuid, parent_tenant_uuid, name, domain_name, enabled, insert_user)
VALUES (
    gen_random_uuid(),  -- Generate a unique UUID for the Tenant
    NULL,               -- No parent Tenant (this is a main Tenant)
    'Default',          -- Tenant Name
    '192.168.10.22',    -- Unique domain name
    true,               -- Tenant is enabled
    NULL                -- No user assigned yet (can be updated later)
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
