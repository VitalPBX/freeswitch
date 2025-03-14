#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import logging

# Configure logging to record migration progress and errors
logging.basicConfig(
    filename='migration.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# ODBC Data Source Name (DSN) defined in /etc/odbc.ini
ODBC_DSN = "ring2all"

# Directory containing user XML files
USER_DIR = "/etc/freeswitch/directory/default/"
DEFAULT_TENANT_NAME = "Default"
INSERT_USER = None  # UUID of the user performing the migration (None if not applicable)

def connect_db():
    """
    Establishes a connection to the database using ODBC.
    The DSN must be configured in /etc/odbc.ini.
    """
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("Successfully connected to the database via ODBC.")
        return conn
    except Exception as e:
        logging.error(f"Failed to connect to the database: {e}")
        raise

def get_tenant_uuid(conn):
    """
    Retrieves the UUID of the default tenant from the database.
    If the tenant does not exist, an error is logged.
    """
    try:
        cur = conn.cursor()
        cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
        result = cur.fetchone()
        cur.close()
        
        if result:
            logging.info(f"Tenant '{DEFAULT_TENANT_NAME}' found with UUID: {result[0]}")
            return result[0]
        else:
            raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' not found.")
    except Exception as e:
        logging.error(f"Error retrieving tenant UUID: {e}")
        raise

def process_user_xml(file_path):
    """
    Parses an XML user file and extracts relevant SIP user data.
    If an error occurs, the function returns None.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        user = root.find(".//user")
        if user is not None:
            user_id = user.get("id")
            params = {param.get("name"): param.get("value") for param in user.findall(".//param")}
            variables = {var.get("name"): var.get("value") for var in user.findall(".//variable")}

            # Ensure password matches user_id for security purposes
            password = user_id
            logging.info(f"Processed user XML for {user_id}, setting password to {password}")

            return {
                "username": user_id,
                "password": password,
                "vm_password": params.get("vm-password", user_id),
                "extension": user_id,
                "toll_allow": variables.get("toll_allow"),
                "accountcode": variables.get("accountcode"),
                "user_context": variables.get("user_context", "default"),
                "effective_caller_id_name": variables.get("effective_caller_id_name", f"Extension {user_id}"),
                "effective_caller_id_number": variables.get("effective_caller_id_number", user_id)
            }
    except Exception as e:
        logging.error(f"Error processing {file_path}: {e}")
        return None

def insert_sip_user(conn, tenant_uuid, user_data):
    """
    Inserts or updates a SIP user into the database using the extracted XML data.
    If the user already exists, it updates their information.
    """
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO public.sip_users (
                tenant_uuid, username, password, vm_password, extension,
                toll_allow, accountcode, user_context,
                effective_caller_id_name, effective_caller_id_number, insert_user
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (username) 
            DO UPDATE SET 
                password = EXCLUDED.password,
                vm_password = EXCLUDED.vm_password,
                extension = EXCLUDED.extension,
                toll_allow = EXCLUDED.toll_allow,
                accountcode = EXCLUDED.accountcode,
                user_context = EXCLUDED.user_context,
                effective_caller_id_name = EXCLUDED.effective_caller_id_name,
                effective_caller_id_number = EXCLUDED.effective_caller_id_number
        """, (
            tenant_uuid, user_data["username"], user_data["password"], user_data["vm_password"],
            user_data["extension"], user_data["toll_allow"], user_data["accountcode"],
            user_data["user_context"], user_data["effective_caller_id_name"],
            user_data["effective_caller_id_number"], INSERT_USER
        ))
        
        conn.commit()
        logging.info(f"User {user_data['username']} inserted/updated successfully.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting/updating user {user_data['username']}: {e}")
        raise

def migrate_users(conn, tenant_uuid):
    """
    Reads XML files from the user directory and inserts users into the database.
    """
    for filename in os.listdir(USER_DIR):
        if filename.endswith(".xml"):
            file_path = os.path.join(USER_DIR, filename)
            user_data = process_user_xml(file_path)
            if user_data:
                insert_sip_user(conn, tenant_uuid, user_data)

def update_all_user_passwords(conn, tenant_uuid):
    """
    Updates all existing users to set their password as their extension number.
    """
    try:
        cur = conn.cursor()
        cur.execute("""
            UPDATE public.sip_users 
            SET password = username 
            WHERE tenant_uuid = ?
        """, (tenant_uuid,))
        
        affected_rows = cur.rowcount
        conn.commit()
        logging.info(f"Updated {affected_rows} users' passwords to match their extensions.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error updating user passwords: {e}")
        raise

def verify_user_1000(conn, tenant_uuid):
    """
    Ensures that user 1000 exists and their password is correctly set.
    Logs the user's final state.
    """
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT username, password FROM public.sip_users WHERE username = '1000' AND tenant_uuid = ?
        """, (tenant_uuid,))
        
        user_1000 = cur.fetchone()
        cur.close()

        if user_1000:
            logging.info(f"User 1000 final state: username={user_1000[0]}, password={user_1000[1]}")
        else:
            logging.warning("User 1000 not found after migration.")
    except Exception as e:
        logging.error(f"Error verifying user 1000: {e}")

def main():
    """
    Executes the migration process:
    1. Establishes a database connection.
    2. Retrieves the default tenant UUID.
    3. Reads XML user files and inserts them into the database.
    4. Ensures all user passwords match their extensions.
    5. Verifies that user 1000 exists.
    """
    conn = None
    try:
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)
        migrate_users(conn, tenant_uuid)
        update_all_user_passwords(conn, tenant_uuid)
        verify_user_1000(conn, tenant_uuid)
        logging.info("Migration completed successfully.")
    except Exception as e:
        logging.error(f"Migration failed: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("Database connection closed.")

if __name__ == "__main__":
    main()
