#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import logging
from xml.dom import minidom  # Import explícito de minidom

# Configuración del logging (guardar en archivo y mostrar en pantalla)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration.log'),
        logging.StreamHandler()  # Muestra en pantalla
    ]
)

# ODBC Data Source Name (DSN) definido en /etc/odbc.ini
ODBC_DSN = "ring2all"

# Directorio de los archivos XML de usuarios
USER_DIR = "/etc/freeswitch/directory/default/"
DEFAULT_TENANT_NAME = "Default"
INSERT_USER = None  # UUID del usuario que realiza la migración (None si no aplica)

# Nueva contraseña fija para todas las extensiones
FIXED_PASSWORD = "r2a2025"

def connect_db():
    """Establece conexión con la base de datos usando ODBC."""
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error conectando a la base de datos: {e}")
        raise

def get_tenant_uuid(conn):
    """Obtiene el UUID del tenant predeterminado desde la base de datos."""
    try:
        cur = conn.cursor()
        cur.execute("SELECT tenant_uuid FROM tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
        result = cur.fetchone()
        cur.close()
        
        if result:
            logging.info(f"🔍 Tenant '{DEFAULT_TENANT_NAME}' encontrado con UUID: {result[0]}")
            return result[0]
        else:
            raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")
    except Exception as e:
        logging.error(f"❌ Error obteniendo UUID del tenant: {e}")
        raise

def clean_and_format_xml(xml_str):
    """
    Elimina la etiqueta <include>, comentarios y formatea el XML con tabulación clara.
    Retorna el XML limpio como string.
    """
    try:
        # Parsear el XML y eliminar comentarios
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=False, insert_pis=False))
        root = ET.fromstring(xml_str, parser=parser)
        
        # Extraer el contenido dentro de <include> (el elemento <user>)
        user_elem = root.find(".//user")
        if user_elem is None:
            raise ValueError("No se encontró la etiqueta <user> en el XML")

        # Convertir solo el elemento <user> a string
        raw_xml = ET.tostring(user_elem, encoding="unicode")
        
        # Formatear con tabulación usando minidom
        formatted_xml = minidom.parseString(raw_xml).toprettyxml(indent="    ")
        
        # Eliminar líneas vacías y la declaración <?xml>
        lines = [line for line in formatted_xml.splitlines() if line.strip()]
        clean_xml = "\n".join(lines[1:])  # Saltar la primera línea (<?xml ...?>)
        
        return clean_xml
    except Exception as e:
        logging.error(f"❌ Error formateando XML: {e}")
        return xml_str  # Devolver original si hay error

def process_user_xml(file_path):
    """Parsea un archivo XML de usuario y extrae los datos relevantes."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        user = root.find(".//user")
        if user is not None:
            user_id = user.get("id")
            params = {param.get("name"): param.get("value") for param in user.findall(".//param")}
            variables = {var.get("name"): var.get("value") for var in user.findall(".//variable")}

            # Reemplazar contraseña en XML y eliminar <include>
            xml_str = ET.tostring(root, encoding="unicode")
            xml_str = xml_str.replace("$${default_password}", FIXED_PASSWORD)
            xml_cleaned = clean_and_format_xml(xml_str)

            logging.info(f"🔹 Procesado usuario {user_id} desde {file_path}")
            return {
                "username": user_id,
                "password": FIXED_PASSWORD,
                "vm_password": params.get("vm-password", user_id),
                "extension": user_id,
                "toll_allow": variables.get("toll_allow"),
                "accountcode": variables.get("accountcode"),
                "user_context": variables.get("user_context", "default"),
                "effective_caller_id_name": variables.get("effective_caller_id_name", f"Extension {user_id}"),
                "effective_caller_id_number": variables.get("effective_caller_id_number", user_id),
                "xml_data": xml_cleaned  # Guardar XML limpio sin <include>
            }
        else:
            logging.warning(f"⚠️ No se encontró usuario en {file_path}")
            return None
    except Exception as e:
        logging.error(f"❌ Error procesando {file_path}: {e}")
        return None

def insert_sip_user(conn, tenant_uuid, user_data):
    """Inserta o actualiza un usuario SIP en la base de datos."""
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO core.sip_users (
                tenant_uuid, username, password, vm_password, extension,
                toll_allow, accountcode, user_context,
                effective_caller_id_name, effective_caller_id_number, xml_data, insert_user
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (username) 
            DO UPDATE SET 
                password = EXCLUDED.password,
                vm_password = EXCLUDED.vm_password,
                extension = EXCLUDED.extension,
                toll_allow = EXCLUDED.toll_allow,
                accountcode = EXCLUDED.accountcode,
                user_context = EXCLUDED.user_context,
                effective_caller_id_name = EXCLUDED.effective_caller_id_name,
                effective_caller_id_number = EXCLUDED.effective_caller_id_number,
                xml_data = EXCLUDED.xml_data
        """, (
            tenant_uuid, user_data["username"], user_data["password"], user_data["vm_password"],
            user_data["extension"], user_data["toll_allow"], user_data["accountcode"],
            user_data["user_context"], user_data["effective_caller_id_name"],
            user_data["effective_caller_id_number"], user_data["xml_data"], INSERT_USER
        ))
        
        conn.commit()
        logging.info(f"✅ Usuario {user_data['username']} insertado/actualizado correctamente.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error insertando/actualizando usuario {user_data['username']}: {e}")
        raise

def migrate_users(conn, tenant_uuid):
    """Lee archivos XML de usuarios y los inserta en la base de datos."""
    logging.info(f"🚀 Iniciando migración de usuarios desde {USER_DIR}")
    for filename in os.listdir(USER_DIR):
        if filename.endswith(".xml"):
            file_path = os.path.join(USER_DIR, filename)
            user_data = process_user_xml(file_path)
            if user_data:
                insert_sip_user(conn, tenant_uuid, user_data)
    logging.info("🏁 Migración de usuarios completada.")

def update_all_user_passwords(conn, tenant_uuid):
    """Actualiza todas las contraseñas de los usuarios existentes a 'r2a2025'."""
    try:
        cur = conn.cursor()
        cur.execute("""
            UPDATE core.sip_users 
            SET password = ? 
            WHERE tenant_uuid = ?
        """, (FIXED_PASSWORD, tenant_uuid))
        
        affected_rows = cur.rowcount
        conn.commit()
        logging.info(f"🔄 Actualizadas {affected_rows} contraseñas a '{FIXED_PASSWORD}'.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error actualizando contraseñas: {e}")
        raise

def verify_user_1000(conn, tenant_uuid):
    """Verifica que el usuario 1000 exista y tenga la contraseña correcta."""
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT username, password FROM core.sip_users WHERE username = '1000' AND tenant_uuid = ?
        """, (tenant_uuid,))
        
        user_1000 = cur.fetchone()
        cur.close()

        if user_1000:
            logging.info(f"🔍 Verificación: username={user_1000[0]}, password={user_1000[1]}")
        else:
            logging.warning("⚠️ Usuario 1000 no encontrado después de la migración.")
    except Exception as e:
        logging.error(f"❌ Error verificando usuario 1000: {e}")

def main():
    """Ejecuta la migración."""
    conn = None
    try:
        logging.info("🌟 Iniciando proceso de migración de usuarios...")
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)
        migrate_users(conn, tenant_uuid)
        update_all_user_passwords(conn, tenant_uuid)
        verify_user_1000(conn, tenant_uuid)
        logging.info("🎉 Migración completada con éxito.")
    except Exception as e:
        logging.error(f"❌ Fallo en la migración: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("🔒 Conexión a la base de datos cerrada.")

if __name__ == "__main__":
    main()
