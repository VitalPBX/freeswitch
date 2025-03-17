#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import logging

# Configuración del logging
logging.basicConfig(
    filename='migration_sip_profiles.log',
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# ODBC Data Source Name (DSN) definido en /etc/odbc.ini
ODBC_DSN = "ring2all"

# Carpeta donde se encuentran los perfiles SIP
SIP_PROFILES_DIR = "/etc/freeswitch/sip_profiles/"
DEFAULT_TENANT_NAME = "Default"


def connect_db():
    """Establece conexión a la base de datos mediante ODBC."""
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("Conexión a la base de datos establecida.")
        return conn
    except Exception as e:
        logging.error(f"Error al conectar a la base de datos: {e}")
        raise


def get_tenant_uuid(conn):
    """Obtiene el UUID del tenant 'Default' desde la base de datos."""
    try:
        cur = conn.cursor()
        logging.debug(f"Buscando tenant UUID para el tenant: {DEFAULT_TENANT_NAME}")
        cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
        result = cur.fetchone()
        cur.close()

        if result:
            logging.info(f"Tenant '{DEFAULT_TENANT_NAME}' encontrado con UUID: {result[0]}")
            return result[0]
        else:
            logging.error(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado en la base de datos.")
            return None
    except Exception as e:
        logging.error(f"Error obteniendo tenant_uuid: {e}")
        return None


def read_xml_file(file_path):
    """Lee un archivo XML y devuelve su contenido como string."""
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            xml_content = file.read()
            return xml_content
    except Exception as e:
        logging.error(f"Error al leer el archivo XML {file_path}: {e}")
        return None


def insert_sip_profile(conn, tenant_uuid, profile_name, xml_content):
    """Inserta o actualiza un perfil SIP en la base de datos."""
    try:
        cur = conn.cursor()
        logging.debug(f"Insertando perfil SIP: {profile_name}")

        cur.execute("""
            INSERT INTO public.sip_profiles (tenant_uuid, profile_name, xml_config, insert_date, update_date)
            VALUES (?, ?, ?, NOW(), NOW())
            ON CONFLICT (profile_name) 
            DO UPDATE SET 
                xml_config = EXCLUDED.xml_config,
                update_date = NOW();
        """, (tenant_uuid, profile_name, xml_content))

        conn.commit()
        logging.info(f"Perfil SIP '{profile_name}' insertado/actualizado correctamente.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error al insertar/actualizar perfil {profile_name}: {e}")
        raise


def migrate_sip_profiles(conn, tenant_uuid):
    """Procesa y migra todos los perfiles SIP desde los archivos XML a la base de datos."""
    logging.debug(f"Buscando archivos XML en: {SIP_PROFILES_DIR}")

    for filename in os.listdir(SIP_PROFILES_DIR):
        if filename.endswith(".xml"):
            file_path = os.path.join(SIP_PROFILES_DIR, filename)
            profile_name = os.path.splitext(filename)[0]  # Quita la extensión .xml

            logging.info(f"Procesando perfil SIP: {profile_name}")

            xml_content = read_xml_file(file_path)
            if xml_content:
                insert_sip_profile(conn, tenant_uuid, profile_name, xml_content)


def main():
    """Ejecuta la migración de perfiles SIP."""
    conn = None
    try:
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)

        if tenant_uuid:
            migrate_sip_profiles(conn, tenant_uuid)
            logging.info("Migración completada exitosamente.")
        else:
            logging.error("No se pudo obtener el tenant_uuid. Abortando migración.")
    except Exception as e:
        logging.error(f"Fallo en la migración: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("Conexión a la base de datos cerrada.")


if __name__ == "__main__":
    main()
