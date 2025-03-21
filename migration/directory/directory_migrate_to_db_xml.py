#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import logging
import uuid
from xml.dom import minidom

# Configuración del logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration.log'),
        logging.StreamHandler()
    ]
)

ODBC_DSN = "ring2all"
USER_DIR = "/etc/freeswitch/directory/"
DOMAIN_XML_PATH = "/etc/freeswitch/directory/default.xml"
DEFAULT_TENANT_NAME = "Default"
INSERT_USER = None
FIXED_PASSWORD = "r2a2025"

def connect_db():
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error conectando a la base de datos: {e}")
        raise

def get_tenant_uuid(conn):
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
    try:
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=False, insert_pis=False))
        root = ET.fromstring(xml_str, parser=parser)
        user_elem = root.find(".//user")
        if user_elem is None:
            raise ValueError("No se encontró la etiqueta <user> en el XML")
        raw_xml = ET.tostring(user_elem, encoding="unicode")
        formatted_xml = minidom.parseString(raw_xml).toprettyxml(indent="    ")
        lines = [line for line in formatted_xml.splitlines() if line.strip()]
        return "\n".join(lines[1:])
    except Exception as e:
        logging.error(f"❌ Error formateando XML: {e}")
        return xml_str

def process_user_xml(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        user = root.find(".//user")
        if user is not None:
            user_id = user.get("id")
            params = {param.get("name"): param.get("value") for param in user.findall(".//param")}
            variables = {var.get("name"): var.get("value") for var in user.findall(".//variable")}
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
                "xml_data": xml_cleaned
            }
        else:
            logging.warning(f"⚠️ No se encontró usuario en {file_path}")
            return None
    except Exception as e:
        logging.error(f"❌ Error procesando {file_path}: {e}")
        return None

def insert_sip_user(conn, tenant_uuid, user_data):
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO core.sip_users (
                tenant_uuid, username, password, vm_password, extension,
                toll_allow, accountcode, user_context,
                effective_caller_id_name, effective_caller_id_number, xml_data, insert_user
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (username) DO UPDATE SET
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
        cur.close()
        logging.info(f"✅ Usuario {user_data['username']} insertado/actualizado correctamente.")
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error insertando usuario {user_data['username']}: {e}")
        raise

def migrate_users(conn, tenant_uuid):
    logging.info(f"🚀 Iniciando migración de usuarios desde {USER_DIR}")
    for root_dir, _, files in os.walk(USER_DIR):
        for filename in files:
            if filename.endswith(".xml"):
                file_path = os.path.join(root_dir, filename)
                user_data = process_user_xml(file_path)
                if user_data:
                    insert_sip_user(conn, tenant_uuid, user_data)
    logging.info("🏁 Migración de usuarios completada.")

def extract_groups_from_directory_xml(base_dir):
    groups = []
    try:
        for root_dir, _, files in os.walk(base_dir):
            for filename in files:
                if filename.endswith(".xml"):
                    file_path = os.path.join(root_dir, filename)
                    try:
                        tree = ET.parse(file_path)
                        root = tree.getroot()
                        group_elements = root.findall(".//group")
                        for group_elem in group_elements:
                            group_name = group_elem.get("name")
                            user_ids = [user.get("id") for user in group_elem.findall(".//user") if user.get("type") == "pointer"]
                            if group_name and user_ids:
                                groups.append((group_name, user_ids))
                    except ET.ParseError:
                        logging.warning(f"⚠️ Archivo XML no válido: {file_path}")
        return groups
    except Exception as e:
        logging.error(f"❌ Error extrayendo grupos del XML: {e}")
        return []

def insert_groups_and_members(conn, tenant_uuid, groups, insert_user=None):
    try:
        cur = conn.cursor()
        for group_name, user_list in groups:
            group_uuid = str(uuid.uuid4())
            cur.execute("""
                SELECT 1 FROM core.user_groups WHERE tenant_uuid = ? AND group_name = ?
            """, (tenant_uuid, group_name))
            if cur.fetchone():
                logging.info(f"⚠️ Grupo '{group_name}' ya existe. Saltando...")
                continue

            cur.execute("""
                INSERT INTO core.user_groups (
                    group_uuid, tenant_uuid, group_name, insert_user
                ) VALUES (?, ?, ?, ?)
            """, (group_uuid, tenant_uuid, group_name, insert_user))

            if user_list:
                placeholders = ','.join('?' for _ in user_list)
                query = f"""
                    SELECT sip_user_uuid, username 
                    FROM core.sip_users 
                    WHERE username IN ({placeholders}) AND tenant_uuid = ?
                """
                cur.execute(query, (*user_list, tenant_uuid))
                users = cur.fetchall()
                for user_uuid, _ in users:
                    # Verificar si ya existe la relación entre grupo y usuario
                    cur.execute("""
                        SELECT 1 FROM core.group_members 
                        WHERE group_uuid = ? AND sip_user_uuid = ?
                    """, (group_uuid, user_uuid))
                    if cur.fetchone():
                        logging.info(f"⚠️ Miembro ya existente en grupo '{group_name}'. Saltando...")
                        continue

                    member_uuid = str(uuid.uuid4())
                    cur.execute("""
                        INSERT INTO core.group_members (
                            member_uuid, group_uuid, sip_user_uuid, insert_user
                        ) VALUES (?, ?, ?, ?)
                    """, (member_uuid, group_uuid, user_uuid, insert_user))
                    cur.execute("""
                        INSERT INTO core.group_members (
                            member_uuid, group_uuid, sip_user_uuid, insert_user
                        ) VALUES (?, ?, ?, ?)
                    """, (member_uuid, group_uuid, user_uuid, insert_user))
            logging.info(f"✅ Grupo '{group_name}' insertado con {len(user_list)} miembros.")
        conn.commit()
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error insertando grupos/miembros: {e}")
        raise

def main():
    conn = None
    try:
        logging.info("🌟 Iniciando proceso de migración...")
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)
        migrate_users(conn, tenant_uuid)

        # Leer grupos desde el archivo de dominio
        groups = extract_groups_from_directory_xml(USER_DIR)
        insert_groups_and_members(conn, tenant_uuid, groups, insert_user=INSERT_USER)

        logging.info("🎉 Migración completada con éxito.")
    except Exception as e:
        logging.error(f"❌ Fallo en la migración: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("🔒 Conexión a la base de datos cerrada.")

if __name__ == "__main__":
    main()
