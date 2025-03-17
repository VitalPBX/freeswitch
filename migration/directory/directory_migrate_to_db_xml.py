#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import logging

# Configuración del log
LOG_FILE = "/tmp/migration.log"
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Configuración de conexión a la base de datos
ODBC_DSN = "ring2all"
USER_BASE_DIR = "/etc/freeswitch/directory/"
DEFAULT_TENANT_NAME = "Default"
INSERT_USER = None  # UUID del usuario que realiza la migración

# Nueva contraseña fija para todas las extensiones
FIXED_PASSWORD = "r2a2025"

def connect_db():
    """Establece la conexión a la base de datos utilizando ODBC."""
    try:
        logging.debug("Connecting to database using ODBC DSN: %s", ODBC_DSN)
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("Successfully connected to the database via ODBC.")
        return conn
    except Exception as e:
        logging.error(f"Failed to connect to the database: {e}")
        raise

def get_tenant_uuid(conn):
    """Obtiene el UUID del tenant 'Default'."""
    try:
        logging.debug("Fetching tenant UUID for tenant: %s", DEFAULT_TENANT_NAME)
        cur = conn.cursor()
        cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
        result = cur.fetchone()
        cur.close()
        
        if result:
            logging.info(f"Tenant '{DEFAULT_TENANT_NAME}' found with UUID: {result[0]}")
            return result[0]
        else:
            logging.error(f"Tenant '{DEFAULT_TENANT_NAME}' not found.")
            return None
    except Exception as e:
        logging.error(f"Error retrieving tenant UUID: {e}")
        return None

def process_user_xml(file_path):
    """Parses an XML user file, replaces variables, and extracts relevant SIP user data."""
    try:
        logging.debug("Processing XML file: %s", file_path)
        tree = ET.parse(file_path)
        root = tree.getroot()
        user = root.find(".//user")
        if user is not None:
            user_id = user.get("id")
            params = {param.get("name"): param.get("value") for param in user.findall(".//param")}
            variables = {var.get("name"): var.get("value") for var in user.findall(".//variable")}

            # Reemplazar $${default_password} con FIXED_PASSWORD en el XML
            xml_string = ET.tostring(root, encoding="utf-8").decode()
            xml_string = xml_string.replace("$${default_password}", FIXED_PASSWORD)

            logging.debug(f"Extracted user: {user_id} from {file_path}")

            return {
                "username": user_id,
                "password": FIXED_PASSWORD,
                "accountcode": variables.get("accountcode", ""),
                "effective_caller_id_name": variables.get("effective_caller_id_name", f"Extension {user_id}"),
                "effective_caller_id_number": variables.get("effective_caller_id_number", user_id),
                "user_context": variables.get("user_context", "default"),
                "xml_config": xml_string,  # Guarda el XML con la variable reemplazada
                "enabled": True  # Asegurar que todas las extensiones estén habilitadas
            }
        else:
            logging.warning(f"No <user> tag found in {file_path}. Skipping file.")
            return None
    except Exception as e:
        logging.error(f"Error processing {file_path}: {e}")
        return None

def insert_sip_extension(conn, tenant_uuid, user_data):
    """Inserta o actualiza una extensión SIP en la base de datos con datos en formato XML."""
    try:
        logging.debug(f"Inserting/updating user: {user_data['username']}")
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO public.sip_extensions (
                extension_uuid, tenant_uuid, extension, password, accountcode, 
                effective_caller_id_name, effective_caller_id_number, user_context, 
                xml_config, enabled, insert_user
            ) VALUES (
                uuid_generate_v4(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT (extension, tenant_uuid) 
            DO UPDATE SET 
                password = EXCLUDED.password,
                accountcode = EXCLUDED.accountcode,
                effective_caller_id_name = EXCLUDED.effective_caller_id_name,
                effective_caller_id_number = EXCLUDED.effective_caller_id_number,
                user_context = EXCLUDED.user_context,
                xml_config = EXCLUDED.xml_config,
                enabled = EXCLUDED.enabled;
        """, (
            tenant_uuid, user_data["username"], user_data["password"], user_data["accountcode"],
            user_data["effective_caller_id_name"], user_data["effective_caller_id_number"],
            user_data["user_context"], user_data["xml_config"], user_data["enabled"], INSERT_USER
        ))
        
        conn.commit()
        logging.info(f"User {user_data['username']} inserted/updated successfully.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting/updating user {user_data['username']}: {e}")
        raise

def migrate_users(conn, tenant_uuid):
    """Recorre recursivamente los directorios de usuarios XML e inserta sus datos en la base de datos."""
    logging.debug(f"Searching for XML user files in: {USER_BASE_DIR}")
    found_files = 0  # Contador para archivos encontrados

    for root_dir, _, files in os.walk(USER_BASE_DIR):  # Recorrer subdirectorios
        for filename in files:
            if filename.endswith(".xml"):
                found_files += 1
                file_path = os.path.join(root_dir, filename)
                logging.info(f"Processing file: {file_path}")
                user_data = process_user_xml(file_path)
                if user_data:
                    insert_sip_extension(conn, tenant_uuid, user_data)

    logging.info(f"Migration completed. {found_files} XML files processed.")

def verify_user_1000(conn, tenant_uuid):
    """Verifica que el usuario 1000 existe y tiene la contraseña correcta en la base de datos."""
    try:
        logging.debug("Verifying user 1000 in database.")
        cur = conn.cursor()
        cur.execute("""
            SELECT extension, password, enabled FROM public.sip_extensions WHERE extension = '1000' AND tenant_uuid = ?
        """, (tenant_uuid,))
        
        user_1000 = cur.fetchone()
        cur.close()

        if user_1000:
            logging.info(f"User 1000 final state: extension={user_1000[0]}, password={user_1000[1]}, enabled={user_1000[2]}")
        else:
            logging.warning("User 1000 not found after migration.")
    except Exception as e:
        logging.error(f"Error verifying user 1000: {e}")

def main():
    """Ejecuta la migración de usuarios SIP."""
    conn = None
    try:
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)
        if not tenant_uuid:
            logging.error("Migration aborted: Tenant UUID not found.")
            return
        
        migrate_users(conn, tenant_uuid)
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
