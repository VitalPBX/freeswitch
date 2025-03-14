import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid
from datetime import datetime

# ODBC Data Source Name (DSN) defined in /etc/odbc.ini
ODBC_DSN = "ring2all"

DIALPLAN_DIR = "/etc/freeswitch/dialplan"
IVR_MENUS_DIR = "/etc/freeswitch/ivr_menus"
DEFAULT_TENANT_NAME = "Default"

# Connect to the database using ODBC
def connect_db():
    conn = pyodbc.connect(f"DSN={ODBC_DSN}")
    return conn

# Function to get tenant UUID
def get_tenant_uuid(conn, tenant_name):
    cur = conn.cursor()
    cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (tenant_name,))
    result = cur.fetchone()
    cur.close()
    return result[0] if result else None

# Function to parse XML and insert data into DB
def migrate_dialplan():
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn, DEFAULT_TENANT_NAME)
    
    for root_dir, _, files in os.walk(DIALPLAN_DIR):
        for file in files:
            if file.endswith(".xml"):
                file_path = os.path.join(root_dir, file)
                print(f"Processing: {file_path}")
                
                tree = ET.parse(file_path)
                xml_root = tree.getroot()
                context_name = xml_root.get('name', 'default')
                
                cur = conn.cursor()
                cur.execute("INSERT INTO public.dialplan_contexts (context_name, tenant_uuid) VALUES (?, ?) ON CONFLICT (tenant_uuid, context_name) DO NOTHING RETURNING context_uuid", (context_name, tenant_uuid))
                context_uuid = cur.fetchone()
                
                for extension in xml_root.findall('.//extension'):
                    extension_name = extension.get('name', 'unnamed')
                    continue_val = extension.get('continue', 'false') == 'true'
                    cur.execute("INSERT INTO public.dialplan_extensions (context_uuid, extension_name, continue) VALUES (?, ?, ?) RETURNING extension_uuid", (context_uuid, extension_name, continue_val))
                    extension_uuid = cur.fetchone()[0]
                    
                    for condition in extension.findall('condition'):
                        field = condition.get('field', '')
                        expression = condition.get('expression', '')
                        break_on_match = condition.get('break', 'on-false')
                        cur.execute("INSERT INTO public.dialplan_conditions (extension_uuid, field, expression, break_on_match) VALUES (?, ?, ?, ?) RETURNING condition_uuid", (extension_uuid, field, expression, break_on_match))
                        condition_uuid = cur.fetchone()[0]
                        
                        for action in condition.findall('action'):
                            application = action.get('application', '')
                            data = action.get('data', '')
                            cur.execute("INSERT INTO public.dialplan_actions (condition_uuid, action_type, application, data) VALUES (?, 'action', ?, ?)", (condition_uuid, application, data))
                
                conn.commit()
                cur.close()
    
    conn.close()
    print("Dialplan migration completed.")

# Function to migrate IVR menus
def migrate_ivr_menus():
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn, DEFAULT_TENANT_NAME)
    
    for root_dir, _, files in os.walk(IVR_MENUS_DIR):
        for file in files:
            if file.endswith(".xml"):
                file_path = os.path.join(root_dir, file)
                print(f"Processing IVR Menu: {file_path}")
                
                tree = ET.parse(file_path)
                xml_root = tree.getroot()
                ivr_name = xml_root.get('name', 'unnamed')
                
                cur = conn.cursor()
                cur.execute("INSERT INTO public.ivr_menus (tenant_uuid, ivr_name) VALUES (?, ?) ON CONFLICT (tenant_uuid, ivr_name) DO NOTHING RETURNING ivr_uuid", (tenant_uuid, ivr_name))
                ivr_uuid = cur.fetchone()
                
                for option in xml_root.findall('.//option'):
                    digits = option.get('digits', '')
                    action = option.get('action', '')
                    param = option.get('param', '')
                    cur.execute("INSERT INTO public.ivr_menu_options (ivr_uuid, digits, action, param) VALUES (?, ?, ?, ?)", (ivr_uuid, digits, action, param))
                
                conn.commit()
                cur.close()
    
    conn.close()
    print("IVR menu migration completed.")

if __name__ == "__main__":
    migrate_dialplan()
    migrate_ivr_menus()
