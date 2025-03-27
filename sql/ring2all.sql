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

-- === TABLES, INDEXES, TRIGGERS, AND DEMO DATA CONTINUE ===
-- === BEGIN FULL SCHEMA DEFINITION ===

-- Create the tenants table to store tenant information
CREATE TABLE core.tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                   -- Unique identifier for the tenant, auto-generated UUID
    parent_tenant_id UUID,                                            -- Optional reference to a parent tenant for hierarchical structure
    name TEXT NOT NULL UNIQUE,                                        -- Unique name of the tenant (e.g., company name)
    domain_name TEXT NOT NULL UNIQUE,                                 -- Unique domain name used in FreeSWITCH (e.g., sip.example.com)
    is_main BOOLEAN DEFAULT FALSE;                                    -- It is used to indicate that you are the primary Tenant
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                            -- Indicates if the tenant is active (TRUE) or disabled (FALSE)
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable for system inserts)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable),
    CONSTRAINT fk_tenants_parent                                      -- Foreign key to support tenant hierarchy
        FOREIGN KEY (parent_tenant_id) REFERENCES core.tenants (id) 
        ON DELETE SET NULL                                            -- Sets parent_tenant_id to NULL if parent is deleted
);

-- Indexes for tenants
CREATE INDEX idx_tenants_name ON core.tenants (name);
CREATE INDEX idx_tenants_domain_name ON core.tenants (domain_name);
CREATE INDEX idx_tenants_enabled ON core.tenants (enabled);
CREATE INDEX idx_tenants_insert_date ON core.tenants (insert_date);

-- Create the tenant_settings table for tenant-specific configurations
CREATE TABLE core.tenant_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                   -- Unique identifier for the setting, auto-generated UUID
    tenant_id UUID NOT NULL,                                          -- Foreign key to the associated tenant
    name TEXT NOT NULL,                                               -- Setting name (e.g., "max_calls")
    value TEXT NOT NULL,                                              -- Setting value (e.g., "100")
    insert_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),      -- Creation timestamp with timezone
    insert_user UUID,                                                 -- UUID of the user who created the record (nullable)
    update_date TIMESTAMP WITH TIME ZONE,                             -- Last update timestamp with timezone (updated by trigger)
    update_user UUID,                                                 -- UUID of the user who last updated the record (nullable),
    CONSTRAINT fk_tenant_settings_tenants                             -- Foreign key to tenants table
        FOREIGN KEY (tenant_id) REFERENCES core.tenants(id) 
        ON DELETE CASCADE,                                            -- Deletes settings when a tenant is removed
    CONSTRAINT unique_tenant_setting UNIQUE (tenant_id, name)       -- Ensures each tenant has unique setting names
);

-- Indexes for tenant_settings
CREATE INDEX idx_tenant_settings_tenant_id ON core.tenant_settings (tenant_id);
CREATE INDEX idx_tenant_settings_name ON core.tenant_settings (name);
CREATE INDEX idx_tenant_settings_insert_date ON core.tenant_settings (insert_date);

-- ===========================
-- Table: core.sip_profiles
-- Description: Defines SIP profiles with multi-transport and port support
-- ===========================

CREATE TABLE core.sip_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique identifier for each SIP profile
    name TEXT NOT NULL UNIQUE,                                             -- Profile name (e.g., internal, external, webrtc)
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant (for multi-tenant scenarios)
    category TEXT DEFAULT 'sofia',                                         -- Main category for grouping profiles (e.g., sofia, directory, etc)
    subcategory TEXT DEFAULT 'default',                                    -- Subcategory for additional profile grouping
    setting_type TEXT DEFAULT 'param'                                      -- Setting Type (e.g., param or variable)
    description TEXT,                                                      -- Optional brief description of the SIP profile
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                 -- Indicates if the profile is active
    setting_order INTEGER DEFAULT 0,                                       -- Display or application order for profiles

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                        -- Creation timestamp (with timezone)
    insert_user UUID,                                                      -- User UUID who created the profile (nullable)
    update_date TIMESTAMPTZ,                                               -- Last update timestamp (auto-updated by triggers)
    update_user UUID                                                       -- User UUID who last updated the profile (nullable)
);

-- Indexes for core.sip_profiles
CREATE INDEX idx_sip_profiles_tenant_id ON core.sip_profiles (tenant_id);      -- Efficient tenant-based queries
CREATE INDEX idx_sip_profiles_category ON core.sip_profiles (category);        -- Optimized queries based on category
CREATE INDEX idx_sip_profiles_subcategory ON core.sip_profiles (subcategory);  -- Optimized queries based on subcategory
CREATE INDEX idx_sip_profiles_insert_user ON core.sip_profiles (insert_user);  -- Faster lookups by creator
CREATE INDEX idx_sip_profiles_update_user ON core.sip_profiles (update_user);  -- Faster lookups by updater

-- ===========================
-- Table: core.sip_profile_settings
-- Description: Key-value settings for SIP profiles
-- ===========================

CREATE TABLE core.sip_profile_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                                -- Unique identifier for each SIP profile setting
    sip_profile_id UUID NOT NULL REFERENCES core.sip_profiles(id) ON DELETE CASCADE, -- Reference to the associated SIP profile (foreign key)
    category TEXT DEFAULT 'default',                                               -- Primary category for setting grouping (e.g., auth, network, media, security)
    subcategory TEXT DEFAULT 'default',                                            -- Subcategory for detailed grouping of settings
    name TEXT NOT NULL,                                                            -- Name of the setting (e.g., rtp-ip, sip-port)
    value TEXT NOT NULL,                                                           -- Assigned value for this specific setting
    setting_order INTEGER DEFAULT 0,                                               -- Determines the order in which settings are applied
    description TEXT,                                                              -- Brief description providing context about the setting
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                         -- Status indicating whether the setting is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                                -- Timestamp marking when the record was created
    insert_user UUID,                                                              -- UUID of the user who created this record (nullable for system inserts)
    update_date TIMESTAMPTZ,                                                       -- Timestamp marking the last update of the record (auto-updated via trigger)
    update_user UUID                                                               -- UUID of the user who last updated this record (nullable)
);

-- Indexes for efficient data retrieval on core.sip_profile_settings
CREATE INDEX idx_sip_profile_settings_profile_id ON core.sip_profile_settings (sip_profile_id); -- Optimizes JOIN operations with sip_profiles
CREATE INDEX idx_sip_profile_settings_name ON core.sip_profile_settings (name);                 -- Improves performance of queries filtering by setting name
CREATE INDEX idx_sip_profile_settings_insert_user ON core.sip_profile_settings (insert_user);   -- Speeds up queries related to the record creator
CREATE INDEX idx_sip_profile_settings_update_user ON core.sip_profile_settings (update_user);   -- Speeds up queries related to the last user who updated the record

-- ===========================
-- Table: core.sip_profile_aliases
-- Description:  SIP profile Aliases
-- ===========================

CREATE TABLE core.sip_profile_aliases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sip_profile_id UUID NOT NULL REFERENCES core.sip_profiles(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,
    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    insert_user UUID,
    update_date TIMESTAMPTZ,
    update_user UUID
);

-- Índices recomendados
CREATE INDEX idx_sip_profile_aliases_profile_id ON core.sip_profile_aliases (sip_profile_id);
CREATE INDEX idx_sip_profile_aliases_alias ON core.sip_profile_aliases (alias);
CREATE INDEX idx_sip_profile_aliases_insert_user ON core.sip_profile_aliases (insert_user);
CREATE INDEX idx_sip_profile_aliases_update_user ON core.sip_profile_aliases (update_user);

-- ===========================
-- Table: core.gateways
-- Description: SIP Gateways used for outbound and inbound communication
-- ===========================

CREATE TABLE core.gateways (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique ID for the gateway
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                  -- Gateway name (must be unique per tenant)
    username TEXT,                                                       -- SIP username (if authentication is required)
    password TEXT,                                                       -- SIP password
    realm TEXT,                                                          -- Authentication realm (optional)
    proxy TEXT,                                                          -- SIP proxy address (e.g., sip.provider.com)
    register BOOLEAN NOT NULL DEFAULT TRUE,                              -- Whether to register to the SIP provider
    register_transport TEXT DEFAULT 'udp',                               -- Transport protocol for registration (udp, tcp, tls)
    expire_seconds INTEGER DEFAULT 3600,                                 -- Expiry time in seconds
    retry_seconds INTEGER DEFAULT 30,                                    -- Retry time on failure
    from_user TEXT,                                                      -- From-user SIP header
    from_domain TEXT,                                                    -- From-domain SIP header
    contact_params TEXT,                                                 -- Additional contact parameters
    context TEXT DEFAULT 'public',                                       -- Dialplan context
    description TEXT,                                                    -- Optional description
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether this gateway is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.gateways
CREATE INDEX idx_gateways_tenant_id ON core.gateways (tenant_id);
CREATE INDEX idx_gateways_name ON core.gateways (name);
CREATE INDEX idx_gateways_enabled ON core.gateways (enabled);

-- ===========================
-- Table: core.gateway_settings
-- Description: Settings for SIP gateways (advanced parameters)
-- ===========================

CREATE TABLE core.gateway_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique ID for the gateway setting
    gateway_id UUID NOT NULL REFERENCES core.gateways(id) ON DELETE CASCADE, -- Associated gateway
    category TEXT DEFAULT 'default',                                      -- Optional grouping/category for the setting
    name TEXT NOT NULL,                                                  -- Setting name (e.g., extension-in-contact)
    value TEXT NOT NULL,                                                 -- Setting value
    setting_type TEXT DEFAULT 'param',                                   -- Type: param | variable | codec | custom

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.gateway_settings
CREATE INDEX idx_gateway_settings_gateway_id ON core.gateway_settings (gateway_id);
CREATE INDEX idx_gateway_settings_name ON core.gateway_settings (name);
CREATE INDEX idx_gateway_settings_type ON core.gateway_settings (setting_type);

-- ===========================
-- Table: core.sip_trunks
-- Description: SIP Trunks aggregating multiple gateways or profiles
-- ===========================

CREATE TABLE core.sip_trunks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                          -- Unique ID for the SIP trunk
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE,  -- Associated tenant
    name TEXT NOT NULL,                                                     -- Name of the trunk (unique per tenant)
    description TEXT,                                                       -- Optional description
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                  -- Whether this trunk is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                         -- Created timestamp
    insert_user UUID,                                                       -- Created by
    update_date TIMESTAMPTZ,                                                -- Last update timestamp
    update_user UUID                                                        -- Updated by
);

-- Indexes for core.sip_trunks
CREATE INDEX idx_sip_trunks_tenant_id ON core.sip_trunks (tenant_id);
CREATE INDEX idx_sip_trunks_name ON core.sip_trunks (name);
CREATE INDEX idx_sip_trunks_enabled ON core.sip_trunks (enabled);

-- ===========================
-- Table: core.trunk_gateways
-- Description: Link table between trunks and gateways
-- ===========================

CREATE TABLE core.trunk_gateways (
    trunk_id UUID NOT NULL REFERENCES core.sip_trunks(id) ON DELETE CASCADE,   -- Linked trunk
    gateway_id UUID NOT NULL REFERENCES core.gateways(id) ON DELETE CASCADE,   -- Linked gateway
    priority INTEGER DEFAULT 1,                                                -- Order of preference
    PRIMARY KEY (trunk_id, gateway_id)                                         -- Composite key
);

-- ===========================
-- Table: core.media_services
-- Description: Media services configuration (e.g., IVR, announcements, hold music)
-- ===========================

CREATE TABLE core.media_services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique ID
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                   -- Name of the media service
    type TEXT NOT NULL,                                                   -- Type of service (e.g., ivr, announcement, moh)
    description TEXT,                                                     -- Optional description
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Whether this service is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Created timestamp
    insert_user UUID,                                                     -- Created by
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Updated by
);

-- Indexes for core.media_services
CREATE INDEX idx_media_services_tenant_id ON core.media_services (tenant_id);
CREATE INDEX idx_media_services_name ON core.media_services (name);
CREATE INDEX idx_media_services_type ON core.media_services (type);
CREATE INDEX idx_media_services_enabled ON core.media_services (enabled);

-- ===========================
-- Table: core.webrtc_profiles
-- Description: Configuration for WebRTC profiles
-- ===========================

CREATE TABLE core.webrtc_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique ID for the WebRTC profile
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                   -- Name of the WebRTC profile
    description TEXT,                                                     -- Optional description
    stun_server TEXT,                                                     -- Optional STUN server
    turn_server TEXT,                                                     -- Optional TURN server
    turn_user TEXT,                                                       -- TURN username
    turn_password TEXT,                                                   -- TURN password
    wss_url TEXT,                                                         -- WebSocket URL for signaling
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Whether WebRTC is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Created timestamp
    insert_user UUID,                                                     -- Created by
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Updated by
);

-- Indexes for core.webrtc_profiles
CREATE INDEX idx_webrtc_profiles_tenant_id ON core.webrtc_profiles (tenant_id);
CREATE INDEX idx_webrtc_profiles_name ON core.webrtc_profiles (name);
CREATE INDEX idx_webrtc_profiles_enabled ON core.webrtc_profiles (enabled);

-- ===========================
-- Table: core.sip_users
-- Description: Defines SIP users (extensions) per tenant
-- ===========================

CREATE TABLE core.sip_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                      -- Unique identifier for the SIP user
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Tenant association for multi-tenant environments
    username TEXT NOT NULL,                                              -- SIP username (e.g., extension number)
    password TEXT NOT NULL,                                              -- SIP password (should be securely hashed)
    sip_profile_id, UUID                                                 -- Unique identifier for each SIP profile
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
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Tenant that owns this voicemail box
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

-- =============================================
-- Table: core.dialplan_contexts
-- Description: Dialplan Contexts Table
-- =============================================
CREATE TABLE core.dialplan_contexts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                         -- Unique identifier for the context
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Tenant that owns this context
    name TEXT NOT NULL,                                                    -- Context name (e.g., 'default', 'public')
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                 -- Whether the context is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                        -- Creation timestamp
    insert_user UUID,                                                      -- UUID of user who created the record
    update_date TIMESTAMPTZ,                                               -- Last update timestamp
    update_user UUID                                                       -- UUID of user who last updated the record
);

-- Indexes for contexts
CREATE INDEX idx_dialplan_contexts_tenant_id ON core.dialplan_contexts (tenant_id);
CREATE INDEX idx_dialplan_contexts_name ON core.dialplan_contexts (name);

-- =============================================
-- Table: core.dialplan_extensions
-- Description: Dialplan Extensions Table
-- =============================================
CREATE TABLE core.dialplan_extensions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                         -- Unique identifier for the extension
    context_id UUID NOT NULL REFERENCES core.dialplan_contexts(id) ON DELETE CASCADE, -- Associated context
    name TEXT NOT NULL,                                                    -- Extension name (e.g., '1000', 'catch_all')
    priority INTEGER DEFAULT 100,                                          -- Execution priority within the context
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                 -- Whether the extension is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                        -- Creation timestamp
    insert_user UUID,                                                      -- UUID of user who created the record
    update_date TIMESTAMPTZ,                                               -- Last update timestamp
    update_user UUID                                                       -- UUID of user who last updated the record
);

-- Indexes for extensions
CREATE INDEX idx_dialplan_extensions_context_id ON core.dialplan_extensions (context_id);
CREATE INDEX idx_dialplan_extensions_name ON core.dialplan_extensions (name);
CREATE INDEX idx_dialplan_extensions_priority ON core.dialplan_extensions (priority);

-- =============================================
-- Table: core.dialplan_conditions
-- Description: Dialplan Conditions Table
-- =============================================
CREATE TABLE core.dialplan_conditions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                                        -- Unique identifier for the condition
    extension_id UUID NOT NULL REFERENCES core.dialplan_extensions(id) ON DELETE CASCADE,  -- Parent extension to which this condition belongs
    field TEXT NOT NULL,                                                                   -- Field to evaluate (e.g., destination_number)
    expression TEXT NOT NULL,                                                              -- Regex or expression to match against the field
    continue TEXT,                                                                         -- If set to 'true', processing continues to the next extension even if this one matches
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                                 -- Whether the condition is active and should be processed
    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                                        -- Creation timestamp
    insert_user UUID,                                                                      -- UUID of user who created the record (optional)
    update_date TIMESTAMPTZ,                                                               -- Last update timestamp (optional)
    update_user UUID                                                                       -- UUID of user who last updated the record (optional)
);

-- Indexes for conditions
CREATE INDEX idx_dialplan_conditions_extension_id ON core.dialplan_conditions (extension_id);
CREATE INDEX idx_dialplan_conditions_field ON core.dialplan_conditions (field);

-- =============================================
-- Table: core.dialplan_actions
-- Description: Dialplan Actions Table
-- =============================================
CREATE TABLE core.dialplan_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                         -- Unique identifier for the action
    condition_id UUID NOT NULL REFERENCES core.dialplan_conditions(id) ON DELETE CASCADE, -- Parent condition
    application TEXT NOT NULL,                                             -- FreeSWITCH application (e.g., 'answer', 'bridge')
    data TEXT,                                                             -- Application arguments
    type TEXT NOT NULL DEFAULT 'action',                                   -- Type: 'action' or 'anti-action'
    sequence INTEGER DEFAULT 0,                                            -- Order of execution within the condition

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                        -- Creation timestamp
    insert_user UUID,                                                      -- UUID of user who created the record
    update_date TIMESTAMPTZ,                                               -- Last update timestamp
    update_user UUID                                                       -- UUID of user who last updated the record
);

-- Indexes for actions
CREATE INDEX idx_dialplan_actions_condition_id ON core.dialplan_actions (condition_id);
CREATE INDEX idx_dialplan_actions_application ON core.dialplan_actions (application);
CREATE INDEX idx_dialplan_actions_sequence ON core.dialplan_actions (sequence);

-- ===========================
-- Table: core.voicemail_profiles
-- Description: Defines global voicemail profiles with default settings
-- ===========================

CREATE TABLE core.voicemail_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                      -- Unique identifier for the voicemail profile
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                 -- Name of the voicemail profile (e.g., default)
    description TEXT,                                                   -- Optional description of the profile
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                              -- Whether the profile is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                     -- Creation timestamp
    insert_user UUID,                                                   -- Created by
    update_date TIMESTAMPTZ,                                            -- Last update timestamp
    update_user UUID                                                    -- Updated by
);

-- Indexes
CREATE INDEX idx_voicemail_profiles_tenant_id ON core.voicemail_profiles (tenant_id);
CREATE INDEX idx_voicemail_profiles_name ON core.voicemail_profiles (name);

-- ===========================
-- Table: core.voicemail_profile_settings
-- Description: Key-value settings for voicemail profiles
-- ===========================

CREATE TABLE core.voicemail_profile_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique identifier for the voicemail profile setting
    voicemail_profile_id UUID NOT NULL REFERENCES core.voicemail_profiles(id) ON DELETE CASCADE, -- Associated profile
    name TEXT NOT NULL,                                                   -- Name of the setting (e.g., storage-dir, tone-spec)
    value TEXT NOT NULL,                                                  -- Value of the setting
    type TEXT DEFAULT 'param',                                            -- Type: param, variable, etc.
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Whether the setting is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Creation timestamp
    insert_user UUID,                                                     -- Created by
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Updated by
);

-- Indexes
CREATE INDEX idx_voicemail_profile_settings_profile_id ON core.voicemail_profile_settings (voicemail_profile_id);
CREATE INDEX idx_voicemail_profile_settings_name ON core.voicemail_profile_settings (name);

-- ===========================
-- Table: core.ivr
-- Description: Defines IVR menus for call routing and DTMF input
-- ===========================

CREATE TABLE core.ivr (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the IVR menu
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Tenant that owns this IVR
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
    priority INTEGER DEFAULT 100,                                         -- Execution order of this setting
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

-- ===========================
-- Table: core.conference_rooms
-- Description: Defines conference rooms for tenants
-- ===========================

CREATE TABLE core.conference_rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                     -- Unique conference room ID
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                -- Room extension or name
    description TEXT,                                                  -- Optional description
    max_participants INTEGER DEFAULT 50,                               -- Max allowed participants
    moderator_pin TEXT,                                                -- Optional moderator PIN
    participant_pin TEXT,                                              -- Optional participant PIN
    profile TEXT DEFAULT 'default',                                    -- Conference profile (FreeSWITCH)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                             -- Whether the room is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                    -- Created timestamp
    insert_user UUID,                                                  -- Created by
    update_date TIMESTAMPTZ,                                           -- Last update timestamp
    update_user UUID                                                   -- Updated by
);

-- Indexes for core.conference_rooms
CREATE INDEX idx_conference_rooms_tenant_id ON core.conference_rooms (tenant_id); -- Tenant-level filtering
CREATE UNIQUE INDEX uq_conference_rooms_tenant_name ON core.conference_rooms (tenant_id, name); -- Unique name per tenant

-- ===========================
-- Table: core.conference_room_settings
-- Description: Key-value settings for conference rooms
-- ===========================

CREATE TABLE core.conference_room_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                     -- Unique setting ID
    conference_room_id UUID NOT NULL REFERENCES core.conference_rooms(id) ON DELETE CASCADE, -- Related room
    category TEXT,                                                      -- Optional category (media, control, etc.)
    name TEXT NOT NULL,                                                -- Setting name
    value TEXT NOT NULL,                                               -- Setting value
    setting_type TEXT DEFAULT 'media',                                 -- Type: media, control, security, etc.

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                    -- Created timestamp
    insert_user UUID,                                                  -- Created by
    update_date TIMESTAMPTZ,                                           -- Last update timestamp
    update_user UUID                                                   -- Updated by
);

-- Indexes for core.conference_room_settings
CREATE INDEX idx_conference_room_settings_room_id ON core.conference_room_settings (conference_room_id); -- Join by room
CREATE INDEX idx_conference_room_settings_name ON core.conference_room_settings (name); -- Filter by setting name

-- ===========================
-- Table: core.call_center_queues
-- Description: Definition of call center queues
-- ===========================

CREATE TABLE core.call_center_queues (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique queue ID
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                  -- Name of the queue
    strategy TEXT NOT NULL DEFAULT 'longest-idle-agent',                 -- Strategy: ring-all, longest-idle-agent, etc.
    music_on_hold TEXT DEFAULT 'local_stream://default',                 -- MOH class
    max_wait_time INTEGER DEFAULT 0,                                     -- Max wait time in seconds
    max_wait_agents INTEGER DEFAULT 0,                                   -- Max agents before overflowing
    max_no_answer INTEGER DEFAULT 3,                                     -- Max attempts before overflow
    record_calls BOOLEAN DEFAULT FALSE,                                  -- Whether to record calls
    wrap_up_time INTEGER DEFAULT 10,                                     -- Wrap up time after each call
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether the queue is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.call_center_queues
CREATE INDEX idx_call_center_queues_tenant_id ON core.call_center_queues (tenant_id);
CREATE UNIQUE INDEX uq_call_center_queues_name_tenant ON core.call_center_queues (tenant_id, name);

-- ===========================
-- Table: core.call_center_queue_settings
-- Description: Custom settings for queues
-- ===========================

CREATE TABLE core.call_center_queue_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique setting ID
    queue_id UUID NOT NULL REFERENCES core.call_center_queues(id) ON DELETE CASCADE, -- Related queue
    category TEXT,                                                        -- Optional category
    name TEXT NOT NULL,                                                  -- Setting name
    value TEXT NOT NULL,                                                 -- Setting value
    setting_type TEXT DEFAULT 'behavior',                                -- Setting type: behavior, routing, etc.

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.call_center_queue_settings
CREATE INDEX idx_call_center_queue_settings_queue_id ON core.call_center_queue_settings (queue_id);
CREATE INDEX idx_call_center_queue_settings_name ON core.call_center_queue_settings (name);

-- ===========================
-- Table: core.call_center_agents
-- Description: Agents that can participate in queues
-- ===========================

CREATE TABLE core.call_center_agents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique agent ID
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- SIP user associated
    contact TEXT,                                                        -- Agent contact URI (e.g., sofia/internal/1001@domain)
    status TEXT DEFAULT 'Logged Out',                                    -- Status: Available, On Break, etc.
    ready BOOLEAN DEFAULT TRUE,                                          -- Ready to receive calls
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether the agent is enabled

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.call_center_agents
CREATE INDEX idx_call_center_agents_tenant_id ON core.call_center_agents (tenant_id);
CREATE INDEX idx_call_center_agents_user_id ON core.call_center_agents (user_id);

-- ===========================
-- Table: core.call_center_tiers
-- Description: Tier linking agents to queues
-- ===========================

CREATE TABLE core.call_center_tiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique tier ID
    queue_id UUID NOT NULL REFERENCES core.call_center_queues(id) ON DELETE CASCADE, -- Queue associated
    agent_id UUID NOT NULL REFERENCES core.call_center_agents(id) ON DELETE CASCADE, -- Agent associated
    level INTEGER DEFAULT 1,                                             -- Tier level
    position INTEGER DEFAULT 1,                                          -- Agent position within level

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.call_center_tiers
CREATE INDEX idx_call_center_tiers_queue_id ON core.call_center_tiers (queue_id);
CREATE INDEX idx_call_center_tiers_agent_id ON core.call_center_tiers (agent_id);
CREATE UNIQUE INDEX uq_call_center_tiers_combination ON core.call_center_tiers (queue_id, agent_id);

-- ===========================
-- Table: core.recordings
-- Description: Stores metadata about call recordings
-- ===========================

CREATE TABLE core.recordings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the recording
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    user_id UUID REFERENCES core.sip_users(id) ON DELETE SET NULL,       -- Optional owner (SIP user)
    file_path TEXT NOT NULL,                                             -- Absolute or relative path to recording file
    file_name TEXT,                                                      -- Optional file name override
    file_format TEXT DEFAULT 'wav',                                      -- Format of the recording (e.g., wav, mp3)
    call_uuid UUID,                                                      -- UUID of the call associated with recording
    direction TEXT DEFAULT 'inbound',                                    -- Direction: inbound, outbound, internal
    duration INTEGER,                                                    -- Duration of the recording in seconds
    size_bytes BIGINT,                                                   -- Size of the file in bytes
    transcription TEXT,                                                  -- Optional transcription text
    tags TEXT[],                                                         -- Optional array of tags or labels
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Indicates if recording is accessible or archived

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.recordings
CREATE INDEX idx_recordings_tenant_id ON core.recordings (tenant_id);            -- Index for tenant-based filtering
CREATE INDEX idx_recordings_user_id ON core.recordings (user_id);                -- Index for filtering by user
CREATE INDEX idx_recordings_call_uuid ON core.recordings (call_uuid);            -- Index for lookup by call UUID
CREATE INDEX idx_recordings_tags ON core.recordings USING GIN (tags);            -- GIN index for fast tag search

-- ===========================
-- Table: core.time_conditions
-- Description: Defines named time-based conditions (e.g., business hours)
-- ===========================

CREATE TABLE core.time_conditions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the time condition
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                  -- Name of the time condition group
    description TEXT,                                                    -- Optional description
    timezone TEXT DEFAULT 'UTC',                                         -- Time zone of the condition (e.g., America/New_York)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether the condition is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- ===========================
-- Table: core.time_condition_rules
-- Description: Individual rules within a time condition (day/time matching)
-- ===========================

CREATE TABLE core.time_condition_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique rule ID
    condition_id UUID NOT NULL REFERENCES core.time_conditions(id) ON DELETE CASCADE, -- Related time condition group
    day_of_week TEXT[],                                                  -- Days of the week (e.g., ['mon','tue'])
    start_time TIME,                                                     -- Start time (e.g., 08:00)
    end_time TIME,                                                       -- End time (e.g., 17:00)
    start_date DATE,                                                     -- Optional start date (YYYY-MM-DD)
    end_date DATE,                                                       -- Optional end date (YYYY-MM-DD)
    priority INTEGER DEFAULT 0,                                          -- Rule priority order
    action TEXT NOT NULL,                                                -- Action to take if matched (e.g., allow, deny, route)
    destination TEXT,                                                    -- Optional destination (e.g., extension, IVR)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- If the rule is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.time_conditions
CREATE INDEX idx_time_conditions_tenant_id ON core.time_conditions (tenant_id);      -- For filtering by tenant
CREATE INDEX idx_time_condition_rules_condition_id ON core.time_condition_rules (condition_id); -- For fast rule lookup per condition
CREATE INDEX idx_time_condition_rules_day_time ON core.time_condition_rules (day_of_week, start_time, end_time); -- Useful for rule matching

-- ===========================
-- Table: core.blacklist
-- Description: Stores blacklisted numbers or patterns per tenant
-- ===========================

CREATE TABLE core.blacklist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the blacklist entry
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    type TEXT NOT NULL DEFAULT 'number',                                  -- Type of match (e.g., number, pattern, regex)
    value TEXT NOT NULL,                                                  -- Number or pattern to match
    description TEXT,                                                     -- Optional description or label
    source TEXT DEFAULT 'manual',                                         -- Source of entry (e.g., manual, system, API)
    scope TEXT DEFAULT 'inbound',                                         -- Scope of the blacklist (inbound, outbound, all)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- If the blacklist entry is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Created timestamp
    insert_user UUID,                                                     -- Created by
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Updated by
);

-- Indexes for core.blacklist
CREATE INDEX idx_blacklist_tenant_id ON core.blacklist (tenant_id);         -- Index for tenant filtering
CREATE INDEX idx_blacklist_value ON core.blacklist (value);                 -- Index for fast lookup by number/pattern
CREATE INDEX idx_blacklist_scope ON core.blacklist (scope);                 -- Index for filtering by scope

-- ===========================
-- Table: core.call_flows
-- Description: Dynamic call routing based on toggleable states (e.g., night mode)
-- ===========================

CREATE TABLE core.call_flows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the call flow
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                  -- Descriptive name of the call flow (e.g., "Office Night Mode")
    feature_code TEXT UNIQUE,                                            -- Code used to toggle the call flow (e.g., *21)
    status BOOLEAN NOT NULL DEFAULT FALSE,                               -- Current state of the call flow (TRUE = active)
    default_destination TEXT,                                            -- Destination when call flow is off
    alternate_destination TEXT,                                          -- Destination when call flow is on
    toggle_enabled BOOLEAN NOT NULL DEFAULT TRUE,                        -- If the user can manually toggle this flow
    announcement TEXT,                                                   -- Optional audio file path to announce status
    notes TEXT,                                                          -- Internal notes or comments
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- If the call flow is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- ===========================
-- Table: core.call_flow_settings
-- Description: Additional settings for call flows (advanced routing, variables)
-- ===========================

CREATE TABLE core.call_flow_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the setting
    call_flow_id UUID NOT NULL REFERENCES core.call_flows(id) ON DELETE CASCADE, -- Related call flow
    category TEXT NOT NULL DEFAULT 'dialplan',                           -- Logical group for the setting (e.g., dialplan, context, media)
    name TEXT NOT NULL,                                                  -- Parameter or variable name
    value TEXT,                                                          -- Parameter value
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- If this setting is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- ===========================
-- Table: core.forwarding
-- Description: Call forwarding configurations per user and condition
-- ===========================

CREATE TABLE core.forwarding (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the forwarding rule
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- Target user for forwarding
    type TEXT NOT NULL,                                                  -- Type of forwarding (e.g., always, busy, no_answer, unavailable)
    destination TEXT NOT NULL,                                           -- Forward-to destination (e.g., number, extension)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether this forwarding rule is enabled
    delay_seconds INT DEFAULT 0,                                         -- Optional delay before forwarding (used in no_answer type)
    notes TEXT,                                                          -- Optional description or internal note

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- ===========================
-- Table: core.dnd
-- Description: Do Not Disturb settings for SIP users
-- ===========================

CREATE TABLE core.dnd (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for DND rule
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- SIP user the DND rule applies to
    enabled BOOLEAN NOT NULL DEFAULT FALSE,                              -- TRUE if DND is enabled for the user
    reason TEXT,                                                         -- Optional reason or note (e.g., vacation, meeting)
    temporary_until TIMESTAMPTZ,                                         -- Optional end time for temporary DND

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- ===========================
-- Table: core.call_block
-- Description: Blocked numbers and patterns by tenant and optionally per user
-- ===========================

CREATE TABLE core.call_block (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the block entry
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Tenant scope
    user_id UUID REFERENCES core.sip_users(id) ON DELETE CASCADE,        -- Optional user-specific block
    number_pattern TEXT NOT NULL,                                        -- Number or pattern to block (e.g., 1900*, +44*)
    block_type TEXT DEFAULT 'incoming',                                  -- Direction of block: incoming, outgoing, both
    reason TEXT,                                                         -- Description or reason for block
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- TRUE if the block is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- ===========================
-- Table: core.presence
-- Description: Presence tracking for SIP users (manual or auto-generated)
-- ===========================

CREATE TABLE core.presence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique presence entry ID
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Tenant ownership
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- Associated SIP user
    status TEXT NOT NULL,                                                -- Presence status (available, away, busy, etc.)
    note TEXT,                                                           -- Optional note ("In a meeting", etc.)
    manual_override BOOLEAN NOT NULL DEFAULT FALSE,                      -- Whether this was manually set
    expires_at TIMESTAMPTZ,                                              -- When this presence expires (optional)

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Updated timestamp
    update_user UUID                                                     -- Updated by
);

-- ===========================
-- Table: core.hot_desk
-- Description: Hot desking support for temporary SIP user login on devices
-- ===========================

CREATE TABLE core.hot_desk (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique record ID
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Tenant scope
    device_id UUID NOT NULL,                                             -- Unique ID representing device or endpoint
    user_id UUID NOT NULL REFERENCES core.sip_users(id) ON DELETE CASCADE, -- SIP user currently assigned
    login_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Time when user logged in
    logout_time TIMESTAMPTZ,                                             -- Optional logout time
    auto_logout_interval INT,                                            -- Timeout in seconds for automatic logout
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether hot desking is active for this record

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Record creation timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last modified timestamp
    update_user UUID                                                     -- Modified by
);

-- Indexes for core.call_flows
CREATE INDEX idx_call_flows_tenant_id ON core.call_flows (tenant_id);                    -- Fast tenant-based filtering
CREATE INDEX idx_call_flows_feature_code ON core.call_flows (feature_code);              -- Lookup by toggle code

-- Indexes for core.call_flow_settings
CREATE INDEX idx_call_flow_settings_call_flow_id ON core.call_flow_settings (call_flow_id); -- Fast setting lookup per flow
CREATE INDEX idx_call_flow_settings_category ON core.call_flow_settings (category);         -- Filter settings by category

-- Indexes for core.forwarding
CREATE INDEX idx_forwarding_tenant_id ON core.forwarding (tenant_id);                     -- Fast filtering by tenant
CREATE INDEX idx_forwarding_user_id ON core.forwarding (user_id);                         -- Fast filtering by user
CREATE INDEX idx_forwarding_type ON core.forwarding (type);                               -- Filter by forwarding type
CREATE INDEX idx_forwarding_enabled ON core.forwarding (enabled);                         -- Optimize active/inactive queries

-- Indexes for core.dnd
CREATE INDEX idx_dnd_tenant_id ON core.dnd (tenant_id);                                   -- Tenant-based filtering
CREATE INDEX idx_dnd_user_id ON core.dnd (user_id);                                       -- User-level filtering
CREATE INDEX idx_dnd_enabled ON core.dnd (enabled);                                       -- Enabled/disabled state lookup

-- Indexes for core.call_block
CREATE INDEX idx_call_block_tenant_id ON core.call_block (tenant_id);                     -- Filter blocked numbers by tenant
CREATE INDEX idx_call_block_user_id ON core.call_block (user_id);                         -- Filter user-specific blocks
CREATE INDEX idx_call_block_enabled ON core.call_block (enabled);                         -- Optimize active/inactive block lookups

-- Indexes for core.presence
CREATE INDEX idx_presence_tenant_id ON core.presence (tenant_id);                         -- Presence filtering by tenant
CREATE INDEX idx_presence_user_id ON core.presence (user_id);                             -- Filter presence by user
CREATE INDEX idx_presence_status ON core.presence (status);                               -- Presence status quick lookup

-- Indexes for core.hot_desk
CREATE INDEX idx_hot_desk_tenant_id ON core.hot_desk (tenant_id);                         -- Hot desk lookup by tenant
CREATE INDEX idx_hot_desk_user_id ON core.hot_desk (user_id);                             -- Lookup hot desk sessions by user
CREATE INDEX idx_hot_desk_device_id ON core.hot_desk (device_id);                         -- Lookup by device
CREATE INDEX idx_hot_desk_enabled ON core.hot_desk (enabled);                             -- Optimize active sessions

-- ===========================
-- Table: core.fax
-- Description: Fax-to-email and email-to-fax configurations
-- ===========================

CREATE TABLE core.fax (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique identifier for the fax configuration
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    user_id UUID REFERENCES core.sip_users(id) ON DELETE CASCADE,        -- Optional user assigned to this fax
    extension TEXT NOT NULL,                                             -- Extension associated with this fax
    email TEXT NOT NULL,                                                 -- Destination email for received faxes
    direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound', 'both')), -- Direction of fax handling
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether the fax configuration is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.fax
CREATE INDEX idx_fax_tenant_id ON core.fax (tenant_id);                 -- Fax filtering by tenant
CREATE INDEX idx_fax_user_id ON core.fax (user_id);                     -- Lookup fax by user
CREATE INDEX idx_fax_extension ON core.fax (extension);                 -- Lookup by fax extension

-- ===========================
-- Table: core.announcements
-- Description: Audio announcements to be used in IVRs or call flows
-- ===========================

CREATE TABLE core.announcements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique ID for the announcement
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                  -- Name of the announcement
    file_path TEXT NOT NULL,                                             -- Path to the audio file (e.g., /sounds/...) 
    description TEXT,                                                    -- Optional description
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- TRUE if active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.announcements
CREATE INDEX idx_announcements_tenant_id ON core.announcements (tenant_id); -- Lookup by tenant
CREATE INDEX idx_announcements_name ON core.announcements (name);           -- Lookup by name

-- ===========================
-- Table: core.external_numbers
-- Description: External numbers used for routing, forwarding or external dialing
-- ===========================

CREATE TABLE core.external_numbers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                       -- Unique ID for external number
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    number TEXT NOT NULL,                                                -- E.164 formatted number or national format
    label TEXT,                                                          -- Description label (e.g., Sales Line Chile)
    route_to TEXT,                                                       -- Optional routing target (extension, external, etc.)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                               -- Whether number is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                      -- Created timestamp
    insert_user UUID,                                                    -- Created by
    update_date TIMESTAMPTZ,                                             -- Last update timestamp
    update_user UUID                                                     -- Updated by
);

-- Indexes for core.external_numbers
CREATE INDEX idx_external_numbers_tenant_id ON core.external_numbers (tenant_id); -- Lookup by tenant
CREATE INDEX idx_external_numbers_number ON core.external_numbers (number);       -- Fast lookup by number
CREATE INDEX idx_external_numbers_enabled ON core.external_numbers (enabled);     -- Filter active numbers

-- ===========================
-- Table: core.inbound_routes
-- Description: Routing rules for incoming calls
-- ===========================

CREATE TABLE core.inbound_routes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique ID for inbound route
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                   -- Route name
    destination TEXT NOT NULL,                                            -- Destination (e.g., extension, IVR, queue)
    number_pattern TEXT NOT NULL,                                         -- Dialed number pattern (regex or starts with)
    caller_id_filter TEXT,                                                -- Optional filter by caller ID
    priority INTEGER DEFAULT 100,                                         -- Priority of the route (lower = higher priority)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Whether this route is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Created timestamp
    insert_user UUID,                                                     -- Created by
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Updated by
);

-- Indexes for core.inbound_routes
CREATE INDEX idx_inbound_routes_tenant_id ON core.inbound_routes (tenant_id); -- Lookup by tenant
CREATE INDEX idx_inbound_routes_pattern ON core.inbound_routes (number_pattern); -- Lookup by pattern
CREATE INDEX idx_inbound_routes_enabled ON core.inbound_routes (enabled);     -- Filter active rules

-- ===========================
-- Table: core.outbound_routes
-- Description: Routing rules for outgoing calls
-- ===========================

CREATE TABLE core.outbound_routes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique ID for outbound route
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE, -- Associated tenant
    name TEXT NOT NULL,                                                   -- Route name
    dial_pattern TEXT NOT NULL,                                           -- Dial pattern (e.g., ^9\d{8}$)
    prepend TEXT,                                                         -- Digits to prepend before sending to gateway
    strip_digits INTEGER DEFAULT 0,                                       -- Number of digits to strip from beginning
    gateway TEXT NOT NULL,                                                -- Gateway to send the call to
    priority INTEGER DEFAULT 100,                                         -- Route priority
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                -- Whether this route is active

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Created timestamp
    insert_user UUID,                                                     -- Created by
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Updated by
);

-- Indexes for core.outbound_routes
CREATE INDEX idx_outbound_routes_tenant_id ON core.outbound_routes (tenant_id); -- Lookup by tenant
CREATE INDEX idx_outbound_routes_pattern ON core.outbound_routes (dial_pattern); -- Lookup by pattern
CREATE INDEX idx_outbound_routes_gateway ON core.outbound_routes (gateway);      -- Lookup by gateway
CREATE INDEX idx_outbound_routes_enabled ON core.outbound_routes (enabled);      -- Filter active routes

-- ===========================
-- Table: core.global_vars
-- Description: Routing rules for Global Vars
-- ===========================
CREATE TABLE core.global_vars (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),                        -- Unique ID for outbound route
    name TEXT NOT NULL,                                                    -- Variable name
    description TEXT NOT NULL,                                             -- Description
    value TEXT NOT NULL,                                                   -- Variable value
    enabled BOOLEAN NOT NULL DEFAULT TRUE,                                 -- Whether the variable is active
    tenant_id UUID DEFAULT NULL,                                           -- NULL = global, UUID = per-tenant
    is_global BOOLEAN GENERATED ALWAYS AS (tenant_id IS NULL) STORED,      -- Virtual flag for global scope

    insert_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),                       -- Created timestamp
    insert_user UUID,                                                     -- Created by
    update_date TIMESTAMPTZ,                                              -- Last update timestamp
    update_user UUID                                                      -- Updated by
);

-- Indexes
CREATE UNIQUE INDEX idx_global_vars_name_tenant ON core.global_vars (name, tenant_id);
CREATE INDEX idx_global_vars_enabled ON core.global_vars (enabled);
CREATE INDEX idx_global_vars_tenant_enabled ON core.global_vars (tenant_id, enabled);

-- ============================================================================================================

-- ================================================
-- View: view_sip_users
-- Description:
--   Combines core SIP user accounts with their associated settings.
--   Simplifies SIP user lookups from external systems (e.g., Lua scripts).
--   Returns only enabled users and enabled settings.
-- ================================================

CREATE OR REPLACE VIEW view_sip_users AS
SELECT
    su.id AS sip_user_id,
    su.tenant_id,
    su.username,
    su.password,
    su.enabled,
    su.sip_profile_id AS user_profile_id,  -- Incluimos esta columna
    sus.name AS setting_name,
    sus.value AS setting_value,
    'param' AS setting_type  -- o usa 'variable' si sabes que lo son
FROM
    core.sip_users su
LEFT JOIN
    core.sip_user_settings sus ON su.id = sus.sip_user_id
WHERE
    su.enabled = true;

-- ================================================
-- View: view_sip_profiles
-- Description:
--   Combines SIP profiles with their associated settings.
--   Simplifies loading of SIP profile configurations from Lua or other services.
--   Filters to only include enabled profiles and settings.
-- ================================================

CREATE OR REPLACE VIEW view_sip_profiles AS
SELECT
    p.id AS sip_profile_id,
    p.tenant_id,
    p.name AS profile_name,
    p.category,
    s.name AS setting_name,
    s.value AS setting_value,
    s.setting_order
FROM core.sip_profiles p
LEFT JOIN core.sip_profile_settings s
    ON s.sip_profile_id = p.id
WHERE p.enabled = TRUE AND s.enabled = TRUE;

-- ================================================
-- View: view_gateways
-- Description:
--   Combines Gateways with their related settings.
--   Used by the system (e.g., Lua) to load full gateway configurations.
--   Only includes enabled gateways and settings.
-- ================================================
CREATE OR REPLACE VIEW view_gateways AS
SELECT
    g.id AS gateway_id,               -- Unique ID of the gateway
    g.tenant_id,                      -- Tenant that owns this gateway
    g.name AS gateway_name,           -- Gateway name (e.g., provider1)
    g.realm,                          -- Realm (if used)
    g.proxy,                          -- Proxy address (e.g., sip.provider.com)
    g.register,                       -- Whether to register with the gateway
    g.username,                       -- Username for authentication
    g.password,                       -- Password for authentication
    s.name AS setting_name,           -- Setting name (e.g., from-user, codec-prefs)
    s.value AS setting_value,         -- Setting value
    s.setting_type AS setting_type    -- Optional setting type (custom usage)
FROM core.gateways g
LEFT JOIN core.gateway_settings s ON s.gateway_id = g.id
WHERE g.enabled = TRUE;

-- ===================================================
-- View: view_dialplan_expanded
-- Description:
--   Expands the entire dialplan structure into a flat view.
--   Includes context, extensions, conditions, and their actions.
--   Useful for Lua-based runtime dialplan loading in FreeSWITCH.
-- ===================================================
CREATE OR REPLACE VIEW view_dialplan_expanded AS
SELECT
    ctx.tenant_id,                        -- Tenant that owns the context
    ctx.name AS context_name,             -- Dialplan context (e.g., 'default')
    
    ext.id AS extension_id,               -- Extension ID
    ext.name AS extension_name,           -- Extension name (e.g., '1000')
    ext.priority AS extension_priority,   -- Priority/order of the extension
    
    cond.id AS condition_id,              -- Condition ID
    cond.field AS condition_field,        -- Field to evaluate (e.g., destination_number)
    cond.expression AS condition_expr,    -- Regular expression to match

    act.id AS action_id,                  -- Action or anti-action ID
    act.application AS app_name,          -- Application (e.g., bridge, hangup, set)
    act.data AS app_data,                 -- Data or parameters for the application
    act.type AS action_type,              -- 'action' or 'anti-action'
    act.sequence AS action_sequence       -- Execution order within condition

FROM core.dialplan_contexts ctx
JOIN core.dialplan_extensions ext ON ext.context_id = ctx.id
JOIN core.dialplan_conditions cond ON cond.extension_id = ext.id
JOIN core.dialplan_actions act ON act.condition_id = cond.id

WHERE ctx.enabled = TRUE
  AND ext.enabled = TRUE
  AND cond.enabled = TRUE;

-- ===================================================
-- View: view_ivr_menu_options
-- Description:
--   Lists all IVR menus along with their configured DTMF options.
--   Includes action, destination, optional condition, priority, etc.
--   Simplifies runtime IVR menu loading in FreeSWITCH via Lua.
-- ===================================================
CREATE OR REPLACE VIEW view_ivr_menu_options AS
SELECT
    ivr.tenant_id,                        -- Tenant that owns this IVR
    ivr.id AS ivr_id,                     -- Unique ID of the IVR
    ivr.name AS ivr_name,                 -- Human-readable name of the IVR
    ivr.greet_long,                       -- Long greeting audio file
    ivr.greet_short,                      -- Short greeting audio file
    ivr.invalid_sound,                    -- Invalid input sound
    ivr.exit_sound,                       -- Exit sound
    ivr.timeout,                          -- Timeout in seconds
    ivr.max_failures,                     -- Max allowed invalid entries
    ivr.max_timeouts,                     -- Max allowed timeouts
    ivr.direct_dial,                      -- Direct dial enabled (true/false)

    opt.digits,                           -- DTMF digits that trigger the action
    opt.action,                           -- What to do (transfer, submenu, playback, hangup)
    opt.destination,                      -- Destination (extension, dialplan, IVR id, etc.)
    opt.condition,                        -- Optional condition (expression to evaluate)
    opt.break_on_match,                   -- Whether to break after this match
    opt.priority                          -- Option execution order
FROM core.ivr ivr
JOIN core.ivr_settings opt ON opt.ivr_id = ivr.id
WHERE ivr.enabled = TRUE AND opt.enabled = TRUE;

-- ===================================================
-- View: view_call_center_agents_by_queue
-- Description:
--   Displays the association of agents to queues, including tier info.
--   Combines queues, agents, and their SIP contact details.
--   Used to generate live call routing logic in Lua.
-- ===================================================
CREATE OR REPLACE VIEW view_call_center_agents_by_queue AS
SELECT
    q.tenant_id,                      -- Tenant that owns the queue
    q.id AS queue_id,                -- Unique queue ID
    q.name AS queue_name,            -- Queue name

    a.id AS agent_id,                -- Unique agent ID
    a.user_id,                       -- Associated SIP user (nullable)
    a.contact AS agent_contact,      -- SIP contact (e.g., 1000)
    a.status AS agent_status,        -- Agent status (e.g., Logged Out, Available)
    a.ready AS agent_ready,          -- Whether agent is currently ready

    t.level AS tier_level,           -- Tier level (integer)
    t.position AS tier_position,     -- Tier position (integer)
    t.insert_date AS tier_assigned   -- Date the tier was created
FROM core.call_center_queues q
JOIN core.call_center_tiers t ON t.queue_id = q.id
JOIN core.call_center_agents a ON a.id = t.agent_id
WHERE q.enabled = TRUE
  AND a.enabled = TRUE;

-- ===================================================
-- View: view_voicemail_profiles
-- Description:
--   Lists all voicemail profiles and their associated parameters.
--   Combines core.voicemail_profiles and core.voicemail_profile_settings.
--   Used by voicemail modules and Lua scripts to generate config dynamically.
-- ===================================================
CREATE OR REPLACE VIEW view_voicemail_profiles AS
SELECT
    vp.tenant_id,                       -- Tenant that owns the profile
    vp.id AS profile_id,               -- Unique profile ID
    vp.name AS profile_name,           -- Profile name (e.g., default)

    s.name AS setting_name,            -- Setting name (e.g., file-ext, storage-dir)
    s.value AS setting_value,          -- Setting value
    s.type AS setting_type             -- Type/category (e.g., param)

FROM core.voicemail_profiles vp
LEFT JOIN core.voicemail_profile_settings s ON s.voicemail_profile_id = vp.id
WHERE vp.enabled = TRUE
  AND s.enabled = TRUE;

-- ===================================================
-- View: core.v_global_vars
-- Description:
--   Lists all active global variables, both system-wide and per-tenant.
--   Includes a 'scope' field to indicate whether each variable is global or tenant-specific.
--   Used by Lua scripts to dynamically load environment variables
--   based on tenant context, with fallback to global defaults.
--   Variables with NULL tenant_id are considered global.
-- ===================================================
CREATE OR REPLACE VIEW core.v_global_vars AS
SELECT
    COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000') AS tenant_id, -- Global fallback UUID
    name,                                                                     -- Variable name
    description,                                                              -- Description
    value,                                                                    -- Variable value
    CASE
        WHEN tenant_id IS NULL THEN 'global'
        ELSE 'tenant'
    END AS scope                                                              -- Variable scope (global or tenant)
FROM core.global_vars
WHERE enabled = TRUE;

-- ============================================================================================================
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

CREATE TRIGGER trg_set_update_voicemail_profiles
BEFORE UPDATE ON core.voicemail_profiles
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_voicemail_profile_settings
BEFORE UPDATE ON core.voicemail_profile_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_dialplan_contexts
BEFORE UPDATE ON core.dialplan_contexts
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_dialplan_extensions
BEFORE UPDATE ON core.dialplan_extensions
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_dialplan_conditions
BEFORE UPDATE ON core.dialplan_conditions
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_dialplan_actions
BEFORE UPDATE ON core.dialplan_actions
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

CREATE TRIGGER trg_set_update_conference_rooms
BEFORE UPDATE ON core.conference_rooms
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_conference_room_settings
BEFORE UPDATE ON core.conference_room_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_call_center_queues
BEFORE UPDATE ON core.call_center_queues
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_call_center_queue_settings
BEFORE UPDATE ON core.call_center_queue_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_call_center_agents
BEFORE UPDATE ON core.call_center_agents
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_call_center_tiers
BEFORE UPDATE ON core.call_center_tiers
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_recordings
BEFORE UPDATE ON core.recordings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_time_conditions
BEFORE UPDATE ON core.time_conditions
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_time_condition_rules
BEFORE UPDATE ON core.time_condition_rules
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_blacklist
BEFORE UPDATE ON core.blacklist
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_call_flows
BEFORE UPDATE ON core.call_flows
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_call_flow_settings
BEFORE UPDATE ON core.call_flow_settings
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_forwarding
BEFORE UPDATE ON core.forwarding
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_dnd
BEFORE UPDATE ON core.dnd
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_call_block
BEFORE UPDATE ON core.call_block
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_presence
BEFORE UPDATE ON core.presence
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_hot_desk
BEFORE UPDATE ON core.hot_desk
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_fax
BEFORE UPDATE ON core.fax
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_announcements
BEFORE UPDATE ON core.announcements
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_external_numbers
BEFORE UPDATE ON core.external_numbers
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_inbound_routes
BEFORE UPDATE ON core.inbound_routes
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_outbound_routes
BEFORE UPDATE ON core.outbound_routes
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_sip_trunks
BEFORE UPDATE ON core.sip_trunks
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_trunk_gateways
BEFORE UPDATE ON core.trunk_gateways
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_media_services
BEFORE UPDATE ON core.media_services
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_webrtc_profiles
BEFORE UPDATE ON core.webrtc_profiles
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

CREATE TRIGGER trg_set_update_global_vars
BEFORE UPDATE ON core.global_vars
FOR EACH ROW
EXECUTE FUNCTION core.set_update_timestamp();

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

-- Insert demo tenant for testing and default use
INSERT INTO core.tenants (id, parent_tenant_id, name, domain_name, is_main, enabled, insert_user)
VALUES (
    uuid_generate_v4(),                 -- Generate a unique UUID for the tenant
    NULL,                               -- No parent tenant
    'Default',                          -- Tenant name
    '192.168.10.21',                    -- Domain name for FreeSWITCH (can be replaced in install)
    'TRUE',                             -- It is used to indicate that you are the primary Tenant
    TRUE,                               -- Tenant is enabled
    NULL                                -- Inserted by system
);

-- Insert default tenant settings
INSERT INTO core.tenant_settings (tenant_id, name, value)
VALUES
((SELECT id FROM core.tenants WHERE name = 'Default'), 'max_extensions', '100'),
((SELECT id FROM core.tenants WHERE name = 'Default'), 'max_trunks', '10'),
((SELECT id FROM core.tenants WHERE name = 'Default'), 'call_recording', 'true');
