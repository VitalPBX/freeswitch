import os
import xml.etree.ElementTree as ET
import psycopg2
from psycopg2 import sql
import logging

# Configure logging to track migration process
logging.basicConfig(
    filename='sip_profile_migration.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Database connection configuration
db_config = {
    "dbname": "$r2a_database",
    "user": "$r2a_user",
    "password": "$r2a_password",
    "host": "localhost",
    "port": "5432"
}

try:
    # Establish connection to the ring2all database
    conn = psycopg2.connect(**db_config)
    cur = conn.cursor()
    logging.info("Successfully connected to the database.")
except Exception as e:
    logging.error(f"Failed to connect to the database: {e}")
    raise

# Tenant name and user who inserts the data
TENANT_NAME = "Default"
INSERT_USER = None  # UUID of the user performing the migration, None if not applicable

# Fetch the tenant_uuid for the specified tenant
try:
    cur.execute(
        sql.SQL("SELECT tenant_uuid FROM public.tenants WHERE name = %s"),
        (TENANT_NAME,)
    )
    tenant_uuid = cur.fetchone()
    if not tenant_uuid:
        logging.error(f"Tenant '{TENANT_NAME}' not found in the tenants table.")
        raise Exception(f"Tenant '{TENANT_NAME}' not found in the tenants table.")
    tenant_uuid = tenant_uuid[0]
    logging.info(f"Tenant UUID retrieved: {tenant_uuid}")
except Exception as e:
    logging.error(f"Error fetching tenant UUID: {e}")
    raise

# Function to parse a SIP profile XML file and extract data
def process_sip_profile(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        # Log the root element to debug structure
        logging.info(f"Root element in {file_path}: {root.tag}")

        # Check if the root is a <profile> element
        if root.tag == "profile":
            profile_name = root.get("name")
            if not profile_name:
                logging.warning(f"No 'name' attribute found in profile at {file_path}")
                return None

            settings = {}
            gateways = []

            # Extract settings from the profile
            settings_elem = root.find("settings")
            if settings_elem is not None:
                for param in settings_elem.findall("param"):
                    name = param.get("name")
                    value = param.get("value")
                    if name and value:
                        settings[name] = value
            else:
                logging.warning(f"No <settings> found in profile {profile_name} at {file_path}")

            # Extract gateways if present
            gateways_elem = root.find("gateways")
            if gateways_elem is not None:
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
            else:
                logging.info(f"No <gateways> found in profile {profile_name} at {file_path}")

            logging.info(f"Processed SIP profile: {profile_name} from {file_path}")
            return {"name": profile_name, "settings": settings, "gateways": gateways}
    except Exception as e:
        logging.error(f"Error processing {file_path}: {e}")
    return None

# Function to parse a gateway XML file and extract data
def process_gateway(file_path, profile_name):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        # Log the root element to debug structure
        logging.info(f"Root element in {file_path}: {root.tag}")

        # Check if the file contains a <gateway> element
        gateway = root.find(".//gateway")
        if gateway is not None:
            gateway_name = gateway.get("name")
            if not gateway_name:
                logging.warning(f"No 'name' attribute found in gateway at {file_path}")
                return None

            gateway_settings = {}
            for param in gateway.findall("param"):
                name = param.get("name")
                value = param.get("value")
                if name and value:
                    gateway_settings[name] = value

            logging.info(f"Processed gateway: {gateway_name} for profile {profile_name} from {file_path}")
            return {"name": gateway_name, "settings": gateway_settings}
    except Exception as e:
        logging.error(f"Error processing gateway {file_path}: {e}")
    return None

# Directory containing SIP profiles
sip_profiles_dir = "/etc/freeswitch/sip_profiles/"

# Verify if the directory exists and list its contents
if not os.path.exists(sip_profiles_dir):
    logging.error(f"SIP profiles directory {sip_profiles_dir} does not exist")
    raise Exception(f"SIP profiles directory {sip_profiles_dir} does not exist")
else:
    logging.info(f"Scanning SIP profiles directory: {sip_profiles_dir}")

# Process all XML files in the sip_profiles directory and subdirectories
xml_files_found = False
for root_dir, _, files in os.walk(sip_profiles_dir):
    logging.info(f"Checking directory: {root_dir}")
    for filename in files:
        if filename.endswith(".xml"):
            xml_files_found = True
            file_path = os.path.join(root_dir, filename)
            logging.info(f"Found XML file: {file_path}")

            # Process as a profile
            profile_data = process_sip_profile(file_path)
            if profile_data:
                try:
                    # Insert or update SIP profile into sip_profiles table
                    cur.execute(
                        sql.SQL("""
                            INSERT INTO public.sip_profiles (
                                tenant_uuid, profile_name, insert_date, insert_user
                            ) VALUES (%s, %s, NOW(), %s)
                            ON CONFLICT (tenant_uuid, profile_name)
                            DO UPDATE SET 
                                update_date = NOW(),
                                update_user = EXCLUDED.insert_user
                            RETURNING profile_uuid
                        """),
                        (tenant_uuid, profile_data["name"], INSERT_USER)
                    )
                    profile_uuid = cur.fetchone()[0]
                    logging.info(f"Inserted/Updated SIP profile: {profile_data['name']} with UUID {profile_uuid}")

                    # Insert settings into sip_profile_settings table
                    for name, value in profile_data["settings"].items():
                        cur.execute(
                            sql.SQL("""
                                INSERT INTO public.sip_profile_settings (
                                    profile_uuid, name, value, insert_date, insert_user
                                ) VALUES (%s, %s, %s, NOW(), %s)
                                ON CONFLICT (profile_uuid, name)
                                DO UPDATE SET 
                                    value = EXCLUDED.value,
                                    insert_date = NOW(),
                                    insert_user = EXCLUDED.insert_user
                            """),
                            (profile_uuid, name, value, INSERT_USER)
                        )
                        logging.info(f"Inserted/Updated setting: {name}={value} for profile {profile_data['name']}")

                    # Process inline gateways if any
                    for gateway in profile_data["gateways"]:
                        cur.execute(
                            sql.SQL("""
                                INSERT INTO public.sip_profile_gateways (
                                    profile_uuid, gateway_name, insert_date, insert_user
                                ) VALUES (%s, %s, NOW(), %s)
                                ON CONFLICT (profile_uuid, gateway_name)
                                DO UPDATE SET 
                                    insert_date = NOW(),
                                    insert_user = EXCLUDED.insert_user
                                RETURNING gateway_uuid
                            """),
                            (profile_uuid, gateway["name"], INSERT_USER)
                        )
                        gateway_uuid = cur.fetchone()[0]
                        logging.info(f"Inserted/Updated gateway: {gateway['name']} for profile {profile_data['name']} with UUID {gateway_uuid}")

                        # Insert gateway settings into sip_profile_gateway_settings table
                        for name, value in gateway["settings"].items():
                            cur.execute(
                                sql.SQL("""
                                    INSERT INTO public.sip_profile_gateway_settings (
                                        gateway_uuid, name, value, insert_date, insert_user
                                    ) VALUES (%s, %s, %s, NOW(), %s)
                                    ON CONFLICT (gateway_uuid, name)
                                    DO UPDATE SET 
                                        value = EXCLUDED.value,
                                        insert_date = NOW(),
                                        insert_user = EXCLUDED.insert_user
                                """),
                                (gateway_uuid, name, value, INSERT_USER)
                            )
                            logging.info(f"Inserted/Updated gateway setting: {name}={value} for gateway {gateway['name']}")
                except Exception as e:
                    logging.error(f"Error inserting/updating profile {profile_data['name']}: {e}")

            # Process as a gateway if not a profile
            else:
                profile_name = os.path.basename(root_dir)  # e.g., "external" from "/etc/freeswitch/sip_profiles/external"
                gateway_data = process_gateway(file_path, profile_name)
                if gateway_data:
                    try:
                        # Fetch the profile_uuid for the parent profile
                        cur.execute(
                            sql.SQL("SELECT profile_uuid FROM public.sip_profiles WHERE tenant_uuid = %s AND profile_name = %s"),
                            (tenant_uuid, profile_name)
                        )
                        profile_uuid = cur.fetchone()
                        if not profile_uuid:
                            logging.warning(f"Profile {profile_name} not found for gateway {gateway_data['name']} at {file_path}")
                            continue
                        profile_uuid = profile_uuid[0]

                        # Insert or update gateway
                        cur.execute(
                            sql.SQL("""
                                INSERT INTO public.sip_profile_gateways (
                                    profile_uuid, gateway_name, insert_date, insert_user
                                ) VALUES (%s, %s, NOW(), %s)
                                ON CONFLICT (profile_uuid, gateway_name)
                                DO UPDATE SET 
                                    insert_date = NOW(),
                                    insert_user = EXCLUDED.insert_user
                                RETURNING gateway_uuid
                            """),
                            (profile_uuid, gateway_data["name"], INSERT_USER)
                        )
                        gateway_uuid = cur.fetchone()[0]
                        logging.info(f"Inserted/Updated gateway: {gateway_data['name']} for profile {profile_name} with UUID {gateway_uuid}")

                        # Insert gateway settings into sip_profile_gateway_settings table
                        for name, value in gateway_data["settings"].items():
                            cur.execute(
                                sql.SQL("""
                                    INSERT INTO public.sip_profile_gateway_settings (
                                        gateway_uuid, name, value, insert_date, insert_user
                                    ) VALUES (%s, %s, %s, NOW(), %s)
                                    ON CONFLICT (gateway_uuid, name)
                                    DO UPDATE SET 
                                        value = EXCLUDED.value,
                                        insert_date = NOW(),
                                        insert_user = EXCLUDED.insert_user
                                """),
                                (gateway_uuid, name, value, INSERT_USER)
                            )
                            logging.info(f"Inserted/Updated gateway setting: {name}={value} for gateway {gateway_data['name']}")
                    except Exception as e:
                        logging.error(f"Error inserting/updating gateway {gateway_data['name']} for profile {profile_name}: {e}")

    if not files:
        logging.info(f"No files found in directory: {root_dir}")

if not xml_files_found:
    logging.warning(f"No XML files found in {sip_profiles_dir} or its subdirectories")

# Commit the changes and close the connection
try:
    conn.commit()
    logging.info("SIP profile migration completed successfully")
except Exception as e:
    logging.error(f"Error committing changes: {e}")
finally:
    cur.close()
    conn.close()
    logging.info("Database connection closed")
    print("SIP profile migration completed, check sip_profile_migration.log for details.")
