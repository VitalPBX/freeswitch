import os
import xml.etree.ElementTree as ET
import psycopg2
from psycopg2 import sql
import logging

# Configure logging
logging.basicConfig(
    filename='migration.log',
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

# Tenant name and user who inserts the data (adjust as needed)
TENANT_NAME = "Default"  # Name of the default tenant
INSERT_USER = None       # UUID of the user performing the migration (None if not applicable)

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

# Check the current state of user 1000 before migration
try:
    cur.execute(
        sql.SQL("SELECT username, password FROM public.sip_users WHERE username = '1000' AND tenant_uuid = %s"),
        (tenant_uuid,)
    )
    current_user = cur.fetchone()
    if current_user:
        logging.info(f"Before migration - User 1000: username={current_user[0]}, password={current_user[1]}")
    else:
        logging.info("Before migration - User 1000 not found in sip_users")
except Exception as e:
    logging.error(f"Error checking user 1000 before migration: {e}")

# Function to parse a user XML file and extract relevant data
def process_user_xml(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        user = root.find(".//user")
        if user is not None:
            user_id = user.get("id")
            params = {param.get("name"): param.get("value") for param in user.findall(".//param")}
            variables = {var.get("name"): param.get("value") for param in user.findall(".//variable")}
            # Use the user_id (extension number) as the password, overriding any existing value
            password = params.get("password")
            if password is None or password.startswith("${"):  # Force password to user_id
                password = user_id
            logging.info(f"Processed user XML for {user_id}, setting password to {password}")
            return {
                "username": user_id,
                "password": password,
                "vm_password": params.get("vm-password", user_id),  # Use user_id as vm-password if not defined
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

# Insert groups into the groups table
groups = ["default", "sales", "billing", "support"]
for group_name in groups:
    try:
        cur.execute(
            sql.SQL("""
                INSERT INTO public.groups (tenant_uuid, group_name, insert_user)
                VALUES (%s, %s, %s)
                ON CONFLICT DO NOTHING
                RETURNING group_uuid
            """),
            (tenant_uuid, group_name, INSERT_USER)
        )
        logging.info(f"Inserted group: {group_name}")
    except Exception as e:
        logging.error(f"Error inserting group {group_name}: {e}")
conn.commit()

# Process all XML files in /etc/freeswitch/directory/default/
user_dir = "/etc/freeswitch/directory/default/"
for filename in os.listdir(user_dir):
    if filename.endswith(".xml"):
        file_path = os.path.join(user_dir, filename)
        user_data = process_user_xml(file_path)
        if user_data:
            try:
                # Insert or update user data into sip_users table
                cur.execute(
                    sql.SQL("""
                        INSERT INTO public.sip_users (
                            tenant_uuid, username, password, vm_password, extension,
                            toll_allow, accountcode, user_context,
                            effective_caller_id_name, effective_caller_id_number, insert_user
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
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
                        RETURNING sip_user_uuid
                    """),
                    (
                        tenant_uuid, user_data["username"], user_data["password"], user_data["vm_password"],
                        user_data["extension"], user_data["toll_allow"], user_data["accountcode"],
                        user_data["user_context"], user_data["effective_caller_id_name"],
                        user_data["effective_caller_id_number"], INSERT_USER
                    )
                )
                sip_user_uuid = cur.fetchone()[0]
                logging.info(f"Inserted/Updated user: {user_data['username']} with UUID {sip_user_uuid}, password set to {user_data['password']}")
                
                # Associate the user with the "default" group
                cur.execute(
                    sql.SQL("SELECT group_uuid FROM public.groups WHERE group_name = 'default' AND tenant_uuid = %s"),
                    (tenant_uuid,)
                )
                group_uuid = cur.fetchone()[0]
                cur.execute(
                    sql.SQL("""
                        INSERT INTO public.user_groups (sip_user_uuid, group_uuid, tenant_uuid, insert_user)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT DO NOTHING
                    """),
                    (sip_user_uuid, group_uuid, tenant_uuid, INSERT_USER)
                )
                logging.info(f"Associated user {user_data['username']} with default group")
            except Exception as e:
                logging.error(f"Error inserting/updating user {user_data['username']}: {e}")

# Process specific group assignments from default.xml
default_xml_path = "/etc/freeswitch/directory/default.xml"
try:
    tree = ET.parse(default_xml_path)
    root = tree.getroot()
    logging.info("Parsed default.xml successfully")
except Exception as e:
    logging.error(f"Error parsing default.xml: {e}")

# Define group memberships from the XML
group_users = {
    "sales": ["1000", "1001", "1002", "1003", "1004"],
    "billing": ["1005", "1006", "1007", "1008", "1009"],
    "support": ["1010", "1011", "1012", "1013", "1014"]
}

# Insert users into their respective groups
for group_name, users in group_users.items():
    try:
        cur.execute(
            sql.SQL("SELECT group_uuid FROM public.groups WHERE group_name = %s AND tenant_uuid = %s"),
            (group_name, tenant_uuid)
        )
        group_uuid = cur.fetchone()
        if group_uuid:
            group_uuid = group_uuid[0]
            for user_id in users:
                cur.execute(
                    sql.SQL("SELECT sip_user_uuid FROM public.sip_users WHERE username = %s AND tenant_uuid = %s"),
                    (user_id, tenant_uuid)
                )
                result = cur.fetchone()
                if result:
                    cur.execute(
                        sql.SQL("""
                            INSERT INTO public.user_groups (sip_user_uuid, group_uuid, tenant_uuid, insert_user)
                            VALUES (%s, %s, %s, %s)
                            ON CONFLICT DO NOTHING
                        """),
                        (result[0], group_uuid, tenant_uuid, INSERT_USER)
                    )
                    logging.info(f"Assigned user {user_id} to group {group_name}")
    except Exception as e:
        logging.error(f"Error assigning users to group {group_name}: {e}")

# Explicitly update all existing users to set password to their extension number
try:
    cur.execute(
        sql.SQL("""
            UPDATE public.sip_users 
            SET password = username 
            WHERE tenant_uuid = %s AND (password IS NULL OR password LIKE '%${{default_password}}%')
        """),
        (tenant_uuid,)
    )
    affected_rows = cur.rowcount  # Get the number of rows affected
    logging.info(f"Updated {affected_rows} existing users' passwords to their extension numbers")
except Exception as e:
    logging.error(f"Error updating passwords for existing users: {e}")

# Force update password for user 1000 to ensure it’s set correctly
try:
    cur.execute(
        sql.SQL("""
            UPDATE public.sip_users 
            SET password = '1000' 
            WHERE username = '1000' AND tenant_uuid = %s
        """),
        (tenant_uuid,)
    )
    affected_rows = cur.rowcount
    logging.info(f"Forced password update for user 1000 to '1000', affected {affected_rows} rows")
except Exception as e:
    logging.error(f"Error forcing password update for user 1000: {e}")

# Verify the final state of user 1000
try:
    cur.execute(
        sql.SQL("SELECT username, password FROM public.sip_users WHERE username = '1000' AND tenant_uuid = %s"),
        (tenant_uuid,)
    )
    final_user = cur.fetchone()
    if final_user:
        logging.info(f"After migration - User 1000: username={final_user[0]}, password={final_user[1]}")
    else:
        logging.info("After migration - User 1000 not found in sip_users")
except Exception as e:
    logging.error(f"Error verifying user 1000 after migration: {e}")

# Commit the changes and close the connection
try:
    conn.commit()
    logging.info("Migration completed successfully")
except Exception as e:
    logging.error(f"Error committing changes: {e}")
finally:
    cur.close()
    conn.close()
    logging.info("Database connection closed")
    print("Migration completed, check migration.log for details.")
