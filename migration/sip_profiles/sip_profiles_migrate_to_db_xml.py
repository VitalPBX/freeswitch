#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid
import xml.dom.minidom
import logging

# Configuración del logging
logging.basicConfig(
    filename='migration_sip_profiles.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# ODBC Data Source Name (DSN) definido en /etc/odbc.ini
ODBC_DSN = "ring2all"

# Directorio donde están los perfiles SIP en XML
SIP_PROFILES_DIR = "/etc/freeswitch/sip_profiles"

def connect_db():
    """Establece la conexión con la base de datos."""
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"Error conectando a la base de datos: {e}")
        raise

def clean_xml(xml_str):
    """Elimina comentarios y formatea el XML con tabulación."""
    try:
        root = ET.fromstring(xml_str)

        # Eliminar comentarios
        for elem in root.findall(".//comment()"):
            elem.getparent().remove(elem)

        # Convertir de nuevo a string
        raw_xml = ET.tostring(root, encoding="unicode")
        formatted_xml = xml.dom.minidom.parseString(raw_xml).toprettyxml(indent="    ")

        # Eliminar líneas vacías generadas por minidom
        return "\n".join([line for line in formatted_xml.split("\n") if line.strip()])
    except Exception as e:
        logging.error(f"Error formateando XML: {e}")
        return xml_str  # Retornar original en caso de fallo

def process_sip_profile(file_path):
    """Parsea un archivo XML de perfil SIP, limpia comentarios y tabula correctamente."""
    try:
        with open(file_path, "r") as f:
            xml_str = f.read()

        # Limpiar y tabular XML
        xml_cleaned = clean_xml(xml_str)

        # Obtener el nombre del perfil desde el XML
        root = ET.fromstring(xml_cleaned)
        profile_element = root.find(".//profile")
        profile_name = profile_element.get("name") if profile_element is not None else None

        if not profile_name:
            logging.warning(f"Perfil sin nombre en archivo: {file_path}")
            return None, None

        logging.info(f"Procesado perfil SIP: {profile_name}")
        return profile_name, xml_cleaned
    except Exception as e:
        logging.error(f"Error procesando {file_path}: {e}")
        return None, None

def insert_sip_profile(conn, tenant_uuid, profile_name, xml_data):
    """Inserta o actualiza un perfil SIP en la base de datos."""
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO public.sip_profiles (
                tenant_uuid, profile_name, xml_data, insert_user
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT (tenant_uuid, profile_name) 
            DO UPDATE SET xml_data = EXCLUDED.xml_data
        """, (tenant_uuid, profile_name, xml_data, None))
        
        conn.commit()
        logging.info(f"Perfil SIP {profile_name} insertado/actualizado correctamente.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error insertando/actualizando perfil SIP {profile_name}: {e}")
        raise

def migrate_sip_profiles():
    """Lee archivos XML de perfiles SIP y los inserta en la base de datos."""
    conn = connect_db()

    # Obtener el tenant global (NULL para perfiles compartidos)
    tenant_uuid = None

    for file_name in os.listdir(SIP_PROFILES_DIR):
        file_path = os.path.join(SIP_PROFILES_DIR, file_name)
        if not os.path.isfile(file_path) or not file_path.endswith(".xml"):
            continue
        
        profile_name, xml_data = process_sip_profile(file_path)
        if profile_name:
            insert_sip_profile(conn, tenant_uuid, profile_name, xml_data)

    conn.close()
    logging.info("✅ Migración de perfiles SIP completada.")

if __name__ == "__main__":
    migrate_sip_profiles()
