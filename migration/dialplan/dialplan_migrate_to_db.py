import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid

# ODBC Data Source Name (DSN) defined in /etc/odbc.ini
ODBC_DSN = "ring2all"

DIALPLAN_DIR = "/etc/freeswitch/dialplan"
IVR_MENUS_DIR = "/etc/freeswitch/ivr_menus"
DEFAULT_TENANT_NAME = "Default"

# Conectar a la base de datos
def connect_db():
    conn = pyodbc.connect(f"DSN={ODBC_DSN}")
    return conn

# Obtener el UUID del tenant
def get_tenant_uuid(conn, tenant_name):
    cur = conn.cursor()
    cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (tenant_name,))
    result = cur.fetchone()
    cur.close()
    return result[0] if result else None

# Obtener el UUID del contexto, o crearlo si no existe
def get_or_create_context_uuid(conn, tenant_uuid, context_name):
    cur = conn.cursor()
    cur.execute("SELECT context_uuid FROM public.dialplan_contexts WHERE tenant_uuid = ? AND context_name = ?", 
                (tenant_uuid, context_name))
    result = cur.fetchone()
    
    if result:
        return result[0]
    
    # Insertar el nuevo contexto
    new_uuid = str(uuid.uuid4())
    cur.execute("INSERT INTO public.dialplan_contexts (context_uuid, tenant_uuid, context_name) VALUES (?, ?, ?)", 
                (new_uuid, tenant_uuid, context_name))
    conn.commit()
    return new_uuid

# Obtener el UUID de una extensión, o insertarla si no existe
def get_or_create_extension_uuid(conn, context_uuid, extension_name, continue_val):
    cur = conn.cursor()
    cur.execute("SELECT extension_uuid FROM public.dialplan_extensions WHERE context_uuid = ? AND extension_name = ?", 
                (context_uuid, extension_name))
    result = cur.fetchone()
    
    if result:
        return result[0]

    # Insertar la extensión
    new_uuid = str(uuid.uuid4())
    cur.execute("INSERT INTO public.dialplan_extensions (extension_uuid, context_uuid, extension_name, continue) VALUES (?, ?, ?, ?)", 
                (new_uuid, context_uuid, extension_name, continue_val))
    conn.commit()
    return new_uuid

# Obtener el UUID de una condición, o insertarla si no existe
def insert_condition(conn, extension_uuid, field, expression, break_on_match):
    cur = conn.cursor()
    new_uuid = str(uuid.uuid4())
    cur.execute("INSERT INTO public.dialplan_conditions (condition_uuid, extension_uuid, field, expression, break_on_match) VALUES (?, ?, ?, ?, ?)", 
                (new_uuid, extension_uuid, field, expression, break_on_match))
    conn.commit()
    return new_uuid

# Insertar una acción
def insert_action(conn, condition_uuid, application, data):
    cur = conn.cursor()
    new_uuid = str(uuid.uuid4())
    cur.execute("INSERT INTO public.dialplan_actions (action_uuid, condition_uuid, action_type, application, data) VALUES (?, ?, 'action', ?, ?)", 
                (new_uuid, condition_uuid, application, data))
    conn.commit()

# Migrar los dialplans desde los XML
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

                # Obtener o crear el contexto
                context_uuid = get_or_create_context_uuid(conn, tenant_uuid, context_name)

                for extension in xml_root.findall('.//extension'):
                    extension_name = extension.get('name', 'unnamed')
                    continue_val = extension.get('continue', 'false') == 'true'

                    # Obtener o crear la extensión
                    extension_uuid = get_or_create_extension_uuid(conn, context_uuid, extension_name, continue_val)

                    for condition in extension.findall('condition'):
                        field = condition.get('field', '')
                        expression = condition.get('expression', '')
                        break_on_match = condition.get('break', 'on-false')

                        # Insertar la condición
                        condition_uuid = insert_condition(conn, extension_uuid, field, expression, break_on_match)

                        for action in condition.findall('action'):
                            application = action.get('application', '')
                            data = action.get('data', '')

                            # Insertar la acción
                            insert_action(conn, condition_uuid, application, data)

    conn.close()
    print("Dialplan migration completed.")

# Migrar los IVR Menús
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
                cur.execute("SELECT ivr_uuid FROM public.ivr_menus WHERE tenant_uuid = ? AND ivr_name = ?", 
                            (tenant_uuid, ivr_name))
                result = cur.fetchone()

                if result:
                    ivr_uuid = result[0]
                else:
                    ivr_uuid = str(uuid.uuid4())
                    cur.execute("INSERT INTO public.ivr_menus (ivr_uuid, tenant_uuid, ivr_name) VALUES (?, ?, ?)", 
                                (ivr_uuid, tenant_uuid, ivr_name))
                    conn.commit()

                for option in xml_root.findall('.//option'):
                    digits = option.get('digits', '')
                    action = option.get('action', '')
                    param = option.get('param', '')

                    cur.execute("INSERT INTO public.ivr_menu_options (ivr_uuid, digits, action, param) VALUES (?, ?, ?, ?)", 
                                (ivr_uuid, digits, action, param))

                conn.commit()
                cur.close()

    conn.close()
    print("IVR menu migration completed.")

if __name__ == "__main__":
    migrate_dialplan()
    migrate_ivr_menus()
