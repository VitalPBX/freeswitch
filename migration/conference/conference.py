#!/usr/bin/env python3

import xml.etree.ElementTree as ET
import pyodbc
import uuid
import logging
from datetime import datetime

# Configuración del logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migrate_conference.log'),
        logging.StreamHandler()
    ]
)

# Configuraciones
ODBC_DSN = "ring2all"
CONFERENCE_XML = "/etc/freeswitch/autoload_configs/conference.conf.xml"
DEFAULT_TENANT_NAME = "Default"
INSERT_USER = None  # o UUID del usuario si aplica

def connect_db():
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"Error conectando a la base de datos: {e}")
        raise

def get_tenant_uuid(conn):
    cur = conn.cursor()
    cur.execute("SELECT tenant_uuid FROM tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
    result = cur.fetchone()
    cur.close()
    if result:
        return result[0]
    else:
        raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")

def migrate_conference(conn, tenant_uuid):
    logging.info(f"🌐 Procesando archivo: {CONFERENCE_XML}")
    tree = ET.parse(CONFERENCE_XML)
    root = tree.getroot()
    cur = conn.cursor()

    # 1. Migrar salas publicadas (advertise)
    for adv in root.findall(".//advertise/room"):
        room_name = adv.get("name")
        status = adv.get("status")
        cur.execute("""
            INSERT INTO core.conference_rooms (
                conference_uuid, tenant_uuid, room_name, status, insert_user
            ) VALUES (?, ?, ?, ?, ?)""",
            str(uuid.uuid4()), tenant_uuid, room_name, status, INSERT_USER)
        logging.info(f"✅ Sala publicada migrada: {room_name}")

    # 2. Migrar grupos de control
    for group in root.findall(".//caller-controls/group"):
        group_name = group.get("name")
        group_uuid = str(uuid.uuid4())
        cur.execute("""
            INSERT INTO core.conference_control_groups (
                group_uuid, tenant_uuid, group_name, insert_user
            ) VALUES (?, ?, ?, ?)
        """, (group_uuid, tenant_uuid, group_name, INSERT_USER))
        for control in group.findall("control"):
            action = control.get("action")
            digits = control.get("digits")
            cur.execute("""
                INSERT INTO core.conference_controls (
                    control_uuid, group_uuid, action, digits, insert_user
                ) VALUES (?, ?, ?, ?, ?)
            """, (str(uuid.uuid4()), group_uuid, action, digits, INSERT_USER))
        logging.info(f"✅ Grupo de control migrado: {group_name}")

    # 3. Migrar perfiles completos como XML
    for profile in root.findall(".//profiles/profile"):
        profile_name = profile.get("name")
        profile_xml = ET.tostring(profile, encoding="unicode")
        cur.execute("""
            INSERT INTO core.conference_profiles (
                profile_uuid, tenant_uuid, profile_name, xml_data, insert_user
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (tenant_uuid, profile_name) DO UPDATE SET
                xml_data = EXCLUDED.xml_data,
                update_date = NOW(),
                update_user = EXCLUDED.insert_user
        """, (str(uuid.uuid4()), tenant_uuid, profile_name, profile_xml, INSERT_USER))
        logging.info(f"✅ Perfil de conferencia migrado: {profile_name}")

    conn.commit()
    cur.close()
    logging.info("🎉 Migración de conferencias completada.")

def main():
    try:
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)
        migrate_conference(conn, tenant_uuid)
    except Exception as e:
        logging.error(f"Error en la migración: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("🔒 Conexión cerrada.")

if __name__ == "__main__":
    main()
