-- File: create_ring2all_cdr.sql
-- Description: Creates and configures the ring2all_cdr database for storing Call Detail Records (CDR)
--              in a FreeSWITCH environment. Includes a single table for CDR with optimized indexes
--              and triggers for automatic timestamp updates.
-- Usage: sudo -u postgres psql -f ring2all_cdr.sql
-- Prerequisites: Replace $r2a_cdr_database and $r2a_cdr_user with actual values before running.

-- Create the ring2all_cdr database if it does not exist
-- Note: This assumes execution as the postgres superuser

CREATE DATABASE $r2a_cdr_database;

-- Connect to the newly created ring2all_cdr database
\connect $r2a_cdr_database

-- Create the CDR (Call Detail Record) table to store call metadata
CREATE TABLE cdr (
    id SERIAL PRIMARY KEY,                           -- Auto-incrementing unique identifier for each CDR entry
    local_ip_v4 INET,                                -- Local IP address where the call was handled (using INET for IP validation)
    caller_id_name VARCHAR(255),                     -- Caller’s name (e.g., "John Doe"), limited to 255 characters, nullable
    caller_id_number VARCHAR(50),                    -- Caller’s phone number (e.g., "+12025550123"), limited to 50 characters, nullable
    destination_number VARCHAR(50),                  -- Destination phone number (e.g., "+12025550124"), limited to 50 characters, nullable
    context VARCHAR(50),                             -- Call context (e.g., "default" or "public"), limited to 50 characters, nullable
    start_stamp TIMESTAMP WITH TIME ZONE,            -- Timestamp when the call started (nullable if call not initiated)
    answer_stamp TIMESTAMP WITH TIME ZONE,           -- Timestamp when the call was answered (nullable if unanswered)
    end_stamp TIMESTAMP WITH TIME ZONE,              -- Timestamp when the call ended (nullable if ongoing)
    duration INTEGER CHECK (duration >= 0),          -- Total call duration in seconds (non-negative, nullable if ongoing)
    billsec INTEGER CHECK (billsec >= 0),            -- Billable duration in seconds (non-negative, nullable if not billable)
    hangup_cause VARCHAR(50),                        -- Reason for call termination (e.g., "NORMAL_CLEARING"), limited to 50 characters, nullable
    uuid UUID NOT NULL UNIQUE,                       -- Unique call identifier (UUID format, required for uniqueness)
    bleg_uuid UUID,                                  -- UUID for the B-leg of the call (nullable if no B-leg)
    accountcode VARCHAR(50),                         -- Account code for billing/tracking (e.g., "ACC123"), limited to 50 characters, nullable
    read_codec VARCHAR(50),                          -- Codec used for reading audio (e.g., "PCMU"), limited to 50 characters, nullable
    write_codec VARCHAR(50)                          -- Codec used for writing audio (e.g., "PCMU"), limited to 50 characters, nullable
);

-- Create indexes to optimize query performance on frequently accessed columns
CREATE INDEX idx_cdr_local_ip_v4 ON cdr (local_ip_v4); 
CREATE INDEX idx_cdr_start_stamp ON dr (start_stamp) WHERE start_stamp IS NOT NULL; -- Index for date-based queries (partial index for nullable column)
CREATE INDEX idx_cdr_caller_id_number ON cdr (caller_id_number) WHERE caller_id_number IS NOT NULL; -- Index for caller number searches
CREATE INDEX idx_cdr_destination_number ON cdr (destination_number) WHERE destination_number IS NOT NULL; -- Index for destination number searches
CREATE INDEX idx_cdr_hangup_cause ON cdr (hangup_cause) WHERE hangup_cause IS NOT NULL; -- Index for hangup cause filtering
CREATE INDEX idx_cdr_accountcode ON cdr (accountcode) WHERE accountcode IS NOT NULL; -- Index for account code queries
CREATE INDEX idx_cdr_uuid ON cdr (uuid);                                            -- Index for UUID lookups (already unique, but explicit index for performance)

-- Create the $r2a_cdr_database role if it does not exist and configure privileges
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$r2a_cdr_user') THEN
        EXECUTE 'CREATE ROLE ' || quote_ident('$r2a_cdr_user') || ' WITH LOGIN PASSWORD ' || quote_literal('$r2a_cdr_password');
    END IF;
END $$;

-- Grant full privileges to the ring2all_cdr user on the database and schema
GRANT ALL PRIVILEGES ON DATABASE $r2a_cdr_database TO $r2a_cdr_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO $r2a_cdr_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $r2a_cdr_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $r2a_cdr_user;
GRANT EXECUTE ON FUNCTION update_timestamp() TO $r2a_cdr_user;
GRANT ALL PRIVILEGES ON cdr TO $r2a_cdr_user;
GRANT ALL PRIVILEGES ON cdr_id_seq TO $r2a_cdr_user;

-- Set ownership of the CDR table and related objects to the ring2all_cdr user
ALTER TABLE cdr OWNER TO $r2a_cdr_user;
ALTER FUNCTION update_timestamp() OWNER TO $r2a_cdr_user;
