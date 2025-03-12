import os
import xml.etree.ElementTree as ET
import psycopg2
from psycopg2 import sql

# Database connection configuration
db_config = {
    "dbname": "$r2a_database",
    "user": "$r2a_user",
    "password": "$r2a_password",
    "host": "localhost",
    "port": "5432"
}

# Establish connection to the ring2all database
conn = psycopg2.connect(**db_config)
cur = conn.cursor()

# Tenant name and user who inserts the data (adjust as needed)
TENANT_NAME = "Default"  # Name of the default tenant
INSERT_USER = None       # UUID of the user performing the migration (None if not applicable)

# Fetch the tenant_uuid for the specified tenant
cur.execute(
    sql.SQL("SELECT tenant_uuid FROM public.tenants WHERE name = %s"),
    (TENANT_NAME,)
)
tenant_uuid = cur.fetchone()
if not tenant_uuid:
    raise Exception(f"Tenant '{TENANT_NAME}' not found in the tenants table.")
tenant_uuid = tenant_uuid[0]

# Function to parse a user XML file and extract relevant data
def process_user_xml(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        user = root.find(".//user")
        if user is not None:
            user_id = user.get("id")
            params = {param.get("name"): param.get("value") for param in user.findall(".//param")}
            variables = {var.get("name"): var.get("value") for var in user.findall(".//variable")}
            # Use the user_id as the default password if not specified in XML
            password = params.get("password")
            if password is None or password.startswith("${"):  # Evita variables como $${default_password}
                password = user_id  # Usa el username como contraseña predeterminada
            return {
                "username": user_id,
                "password": password,
                "vm_password": params.get("vm-password", user_id),  # Usa user_id como vm-password si no está definido
                "extension": user_id,
                "toll_allow": variables.get("toll_allow"),
                "accountcode": variables.get("accountcode"),
                "user_context": variables.get("user_context", "default"),
                "effective_caller_id_name": variables.get("effective_caller_id_name", f"Extension {user_id}"),
                "effective_caller_id_number": variables.get("effective_caller_id_number", user_id)
            }
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
    return None

# Insert groups into the groups table
groups = ["default", "sales", "billing", "support"]
for group_name in groups:
    cur.execute(
        sql.SQL("""
            INSERT INTO public.groups (tenant_uuid, group_name, insert_user)
            VALUES (%s, %s, %s)
            ON CONFLICT DO NOTHING
            RETURNING group_uuid
        """),
        (tenant_uuid, group_name, INSERT_USER)
    )
conn.commit()

# Process all XML files in /etc/freeswitch/directory/default/
user_dir = "/etc/freeswitch/directory/default/"
for filename in os.listdir(user_dir):
    if filename.endswith(".xml"):
        file_path = os.path.join(user_dir, filename)
        user_data = process_user_xml(file_path)
        if user_data:
            # Insert user data into sip_users table
            cur.execute(
                sql.SQL("""
                    INSERT INTO public.sip_users (
                        tenant_uuid, username, password, vm_password, extension,
                        toll_allow, accountcode, user_context,
                        effective_caller_id_name, effective_caller_id_number, insert_user
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (username) DO NOTHING
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

# Process specific group assignments from default.xml
default_xml_path = "/etc/freeswitch/directory/default.xml"
tree = ET.parse(default_xml_path)
root = tree.getroot()

# Define group memberships from the XML
group_users = {
    "sales": ["1000", "1001", "1002", "1003", "1004"],
    "billing": ["1005", "1006", "1007", "1008", "1009"],
    "support": ["1010", "1011", "1012", "1013", "1014"]
}

# Insert users into their respective groups
for group_name, users in group_users.items():
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

# Actualizar la contraseña del usuario 1000 a "1234"
cur.execute(
    sql.SQL("""
        UPDATE public.sip_users 
        SET password = %s 
        WHERE username = %s AND tenant_uuid = %s
    """),
    ("1234", "1000", tenant_uuid)
)

# Commit the changes and close the connection
conn.commit()
cur.close()
conn.close()
print("Migration completed, password for user 1000 updated to '1234'.")
