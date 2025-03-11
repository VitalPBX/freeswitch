-- Create the ring2all_cdr database
CREATE DATABASE $r2a_cdr_database;

-- Connect to the newly created ring2all CDR database
\connect $r2a_cdr_database;

-- Create the CDR (Call Detail Record) table
CREATE TABLE public.cdr (
    id SERIAL PRIMARY KEY,                -- Unique identifier for each record
    tenant_id INT DEFAULT NULL,           -- Tenant identifier (for multi-tenant systems)
    local_ip_v4 VARCHAR(255),             -- Local IP address where the call was handled
    caller_id_name VARCHAR(255),          -- Caller’s name
    caller_id_number VARCHAR(255),        -- Caller’s phone number
    destination_number VARCHAR(255),      -- Destination phone number
    context VARCHAR(255),                 -- Call context (e.g., dial plan, routing)
    start_stamp TIMESTAMP,                -- Call start time
    answer_stamp TIMESTAMP,               -- Time when the call was answered
    end_stamp TIMESTAMP,                  -- Call end time
    duration INTEGER,                      -- Total call duration (in seconds)
    billsec INTEGER,                       -- Billable duration (in seconds)
    hangup_cause VARCHAR(255),            -- Reason for call termination
    uuid VARCHAR(255) UNIQUE,             -- Unique call identifier
    bleg_uuid VARCHAR(255),               -- UUID for the B-leg of the call (if applicable)
    accountcode VARCHAR(255),             -- Account code for billing/tracking
    read_codec VARCHAR(50),               -- Codec used for reading audio
    write_codec VARCHAR(50)               -- Codec used for writing audio
);

-- Set the owner of the table to the specified database user
ALTER TABLE public.cdr OWNER TO $r2a_cdr_user;

-- Create indexes to improve query performance
CREATE INDEX idx_cdr_tenant_id ON public.cdr (tenant_id);                 -- Index for tenant filtering
CREATE INDEX idx_cdr_start_stamp ON public.cdr (start_stamp);             -- Index for date-based queries
CREATE INDEX idx_cdr_caller_id_number ON public.cdr (caller_id_number);   -- Index for searching by caller
CREATE INDEX idx_cdr_destination_number ON public.cdr (destination_number); -- Index for searching by destination
CREATE INDEX idx_cdr_hangup_cause ON public.cdr (hangup_cause);           -- Index for filtering by hangup cause
CREATE INDEX idx_cdr_accountcode ON public.cdr (accountcode);             -- Index for account-based queries
