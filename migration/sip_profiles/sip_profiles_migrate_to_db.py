#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import logging

# Configure logging to track SIP profile migration
logging.basicConfig(
    filename='sip_profile_migration.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# ODBC Data Source Name (DSN) defined in /etc/odbc.ini
ODBC_DSN = "ring2all"

# Directory containing SIP profiles
SIP_PROFILES_DIR = "/etc/freeswitch/sip_profiles/"
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

def process_sip_profile(file_path):
    """
    Parses an XML SIP profile file and extracts its configuration settings.
    Returns a dictionary containing profile name, settings, and gateways.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        # Check if the root element is <profile>
        if root.tag != "profile":
            logging.warning(f"Skipping file {file_path}: Not a valid SIP profile.")
            return None

        profile_name = root.get("name")
        if not profile_name:
            logging.warning(f"No 'name' attribute found in profile at {file_path}")
            return None

        settings = {}
        gateways = []

        # Extract settings from <settings> block
        settings_elem = root.find("settings")
        if settings_elem:
            for param in settings_elem.findall("param"):
                name = param.get("name")
                value = param.get("value")
                if name and value:
                    settings[name] = value
        else:
            logging.warning(f"No <settings> found in profile {profile_name} at {file_path}")

        # Extract gateways from <gateways> block
        gateways_elem = root.find("gateways")
        if gateways_elem:
            for gateway in gateways_elem.findall("gateway"):
                gateway_name = gateway.get("name")
                gateway_settings = {}
                for param in gateway.findall("param"):
                    name = param.get("name")
                    value = param.get("value")
                    if name and value:
                        gateway_settings[name] = value
                if gateway_name:
                    gateways.append({"name": gateway_name, "settings": gateway_settings})

        logging.info(f"Processed SIP profile: {profile_name} from {file_path}")
        return {"name": profile_name, "settings": settings, "gateways": gateways}
    except Exception as e:
        logging.error(f"Error processing {file_path}: {e}")
    return None

def insert_sip_profile(conn, tenant_uuid, profile_data):
    """
    Inserts or updates a SIP profile and its settings in the database.
    """
    try:
        cur = conn.cursor()
        
        # Insert or update SIP profile
        cur.execute("""
            INSERT INTO public.sip_profiles (
                tenant_uuid, profile_name, insert_date, insert_user
            ) VALUES (?, ?, GETDATE(), ?)
            ON CONFLICT (tenant_uuid, profile_name)
            DO UPDATE SET update_date = GETDATE(), update_user = EXCLUDED.insert_user
            RETURNING profile_uuid
        """, (tenant_uuid, profile_data["name"], INSERT_USER))
        
        profile_uuid = cur.fetchone()[0]
        logging.info(f"Inserted/Updated SIP profile: {profile_data['name']} with UUID {profile_uuid}")

        # Insert settings into sip_profile_settings table
        for name, value in profile_data["settings"].items():
            cur.execute("""
                INSERT INTO public.sip_profile_settings (
                    profile_uuid, name, value, insert_date, insert_user
                ) VALUES (?, ?, ?, GETDATE(), ?)
                ON CONFLICT (profile_uuid, name)
                DO UPDATE SET value = EXCLUDED.value, insert_date = GETDATE(), insert_user = EXCLUDED.insert_user
            """, (profile_uuid, name, value, INSERT_USER))
            logging.info(f"Inserted/Updated setting: {name}={value} for profile {profile_data['name']}")

        conn.commit()
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting/updating profile {profile_data['name']}: {e}")
        raise

def migrate_sip_profiles(conn, tenant_uuid):
    """
    Reads XML files from the SIP profiles directory and inserts them into the database.
    """
    if not os.path.exists(SIP_PROFILES_DIR):
        logging.error(f"SIP profiles directory {SIP_PROFILES_DIR} does not exist.")
        raise Exception(f"SIP profiles directory {SIP_PROFILES_DIR} does not exist.")

    logging.info(f"Scanning SIP profiles directory: {SIP_PROFILES_DIR}")
    
    for root_dir, _, files in os.walk(SIP_PROFILES_DIR):
        for filename in files:
            if filename.endswith(".xml"):
                file_path = os.path.join(root_dir, filename)
                logging.info(f"Processing file: {file_path}")

                # Extract profile data from XML
                profile_data = process_sip_profile(file_path)
                if profile_data:
                    insert_sip_profile(conn, tenant_uuid, profile_data)

def main():
    """
    Executes the SIP profile migration process:
    1. Establishes a database connection.
    2. Retrieves the default tenant UUID.
    3. Reads XML SIP profile files and inserts them into the database.
    """
    conn = None
    try:
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)
        migrate_sip_profiles(conn, tenant_uuid)
        logging.info("SIP profile migration completed successfully.")
    except Exception as e:
        logging.error(f"SIP profile migration failed: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("Database connection closed.")

if __name__ == "__main__":
    main()
