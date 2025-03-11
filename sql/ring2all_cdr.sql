-- Cretae ring2all_cdr database
CREATE DATABASE $r2a_cdr_database;

-- Connect to the newly created ring2all_cdr database
\connect $r2a_cdr_database
  
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

GRANT ALL PRIVILEGES ON DATABASE $r2a_cdr_database TO $r2a_cdr_user";
ALTER TABLE public.cdr OWNER TO $r2a_cdr_user;
