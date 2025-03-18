#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid
import xml.dom.minidom
import logging

# Configuración del logging
logging.basicConfig(
    filename='migration_dialplan.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# ODBC Data Source Name (DSN) definido en /etc/odbc.ini
ODBC_DSN = "ring2all"

# Directorios donde están los fragmentos de dialplan e IVR
DIALPLAN_DIR = "/etc/freeswitch/dialplan"
IVR_MENUS_DIR = "/etc/freeswitch/ivr_menus"

# Tenant por defecto
DEFAULT_TENANT_NAME = "Default"

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

def get_tenant_uuid(conn):
    """Obtiene el UUID del tenant por defecto."""
    cur = conn.cursor()
    cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
    result = cur.fetchone()
    cur.close()
    if result:
        return result[0]
    logging.error(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")
    raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")

def process_dialplan(file_path):
    """Parsea un archivo XML de dialplan y extrae cada <extension> como entrada independiente."""
    try:
        with open(file_path, "r") as f:
            xml_str = f.read()

        # Limpiar y tabular XML
        xml_cleaned = clean_xml(xml_str)

        # Parsear el XML
        root = ET.fromstring(xml_cleaned)
        context_name = root.get("name", "default")
        extensions = []

        for extension in root.findall(".//extension"):
            extension_xml = ET.tostring(extension, encoding="unicode")
            formatted_extension_xml = clean_xml(extension_xml)

            # Extraer la expresión sin los caracteres ^ y $
            condition = extension.find(".//condition")
            expression_raw = condition.get("expression", "") if condition is not None else ""
            expression = expression_raw.strip("^$")  # Remover ^ y $

            extensions.append({
                "context_name": context_name,
                "xml_data": formatted_extension_xml,
                "expression": expression
            })

        logging.info(f"Procesado contexto: {context_name} con {len(extensions)} extensiones.")
        return context_name, extensions
    except Exception as e:
        logging.error(f"Error procesando {file_path}: {e}")
        return None, []

def insert_dialplan_context(conn, tenant_uuid, context_name, expression, xml_data):
    """Inserta o actualiza un contexto de dialplan en la base de datos."""
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO public.dialplan_contexts (
                tenant_uuid, context_name, expression, xml_data, insert_user
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (tenant_uuid, context_name) 
            DO UPDATE SET xml_data = EXCLUDED.xml_data, expression = EXCLUDED.expression
        """, (tenant_uuid, context_name, expression, xml_data, None))
        
        conn.commit()
        logging.info(f"Dialplan {context_name} insertado/actualizado correctamente.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error insertando/actualizando dialplan {context_name}: {e}")
        raise

def migrate_dialplan():
    """Lee archivos XML de Dialplan y los inserta en la base de datos."""
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)

    for root_dir, _, files in os.walk(DIALPLAN_DIR):
        for file in files:
            if file.endswith(".xml"):
                file_path = os.path.join(root_dir, file)
                context_name, extensions = process_dialplan(file_path)
                for ext in extensions:
                    insert_dialplan_context(conn, tenant_uuid, ext["context_name"], ext["expression"], ext["xml_data"])

    conn.close()
    logging.info("✅ Migración de dialplan completada.")

def migrate_ivr_menus():
    """Lee archivos XML de IVR y los inserta en la base de datos."""
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)

    for root_dir, _, files in os.walk(IVR_MENUS_DIR):
        for file in files:
            if file.endswith(".xml"):
                file_path = os.path.join(root_dir, file)
                with open(file_path, "r") as f:
                    xml_data = clean_xml(f.read())

                root = ET.fromstring(xml_data)
                ivr_name = root.get("name", "Unnamed IVR")

                try:
                    cur = conn.cursor()
                    cur.execute("""
                        INSERT INTO public.ivr_menus (
                            ivr_uuid, tenant_uuid, ivr_name, xml_data, insert_user
                        ) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT (tenant_uuid, ivr_name) 
                        DO UPDATE SET xml_data = EXCLUDED.xml_data
                    """, (str(uuid.uuid4()), tenant_uuid, ivr_name, xml_data, None))

                    conn.commit()

                    # Manejar opciones del IVR
                    ivr_uuid = cur.execute("SELECT ivr_uuid FROM public.ivr_menus WHERE ivr_name = ?", (ivr_name,)).fetchone()[0]
                    cur.execute("DELETE FROM public.ivr_menu_options WHERE ivr_uuid = ?", (ivr_uuid,))

                    for entry in root.findall(".//entry"):
                        digits = entry.get("digits", "")
                        action = entry.get("action", "")
                        param = entry.get("param", "")

                        cur.execute("""
                            INSERT INTO public.ivr_menu_options (option_uuid, ivr_uuid, digits, action, param)
                            VALUES (?, ?, ?, ?, ?)
                        """, (str(uuid.uuid4()), ivr_uuid, digits, action, param))

                    conn.commit()
                    cur.close()
                    logging.info(f"IVR {ivr_name} y sus opciones insertados/actualizados correctamente.")

                except Exception as e:
                    conn.rollback()
                    logging.error(f"Error insertando/actualizando IVR {ivr_name}: {e}")
                    raise

    conn.close()
    logging.info("✅ Migración de IVR completada.")

if __name__ == "__main__":
    migrate_dialplan()
    migrate_ivr_menus() 
