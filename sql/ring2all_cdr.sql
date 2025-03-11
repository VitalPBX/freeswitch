-- sudo -u postgres psql -d ring2all -f create_ring2all.sql
-- Create the ring2all database as the postgres superuser
CREATE DATABASE ring2all_cdr;

-- Connect to the newly created ring2all_cdr database
\connect ring2all
  
CREATE TABLE public.cdr (
    id SERIAL PRIMARY KEY,
    tenant_id INT DEFAULT NULL,
    local_ip_v4 VARCHAR(255),
    caller_id_name VARCHAR(255),
    caller_id_number VARCHAR(255),
    destination_number VARCHAR(255),
    context VARCHAR(255),
    start_stamp TIMESTAMP,
    answer_stamp TIMESTAMP,
    end_stamp TIMESTAMP,
    duration INTEGER,
    billsec INTEGER,
    hangup_cause VARCHAR(255),
    uuid VARCHAR(255) UNIQUE,
    bleg_uuid VARCHAR(255),
    accountcode VARCHAR(255),
    read_codec VARCHAR(50),
    write_codec VARCHAR(50)
);

ALTER TABLE public.cdr OWNER TO $fs_cdr_user;
