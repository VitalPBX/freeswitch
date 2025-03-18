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

# Directorio donde están los archivos XML de Dialplan
DIALPLAN_DIR = "/etc/freeswitch/dialplan"

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

        # Convertir de nuevo a string eliminando espacios innecesarios
        raw_xml = ET.tostring(root, encoding="unicode")
        formatted_xml = xml.dom.minidom.parseString(raw_xml).toprettyxml(indent="    ")

        # Eliminar líneas vacías generadas por minidom
        return "\n".join([line for line in formatted_xml.split("\n") if line.strip()])
    except Exception as e:
        logging.error(f"Error formateando XML: {e}")
        return None  # Retornar None en caso de fallo

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
        if xml_cleaned is None:
            logging.error(f"XML inválido en archivo: {file_path}")
            return None, []

        # Parsear el XML limpio
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

def insert_or_update_dialplan(conn, tenant_uuid, context_name, expression, xml_data):
    """Inserta o actualiza una entrada en la tabla `dialplan`."""
    if not xml_data:
        logging.warning(f"XML vacío para el contexto {context_name}. No se insertará en la base de datos.")
        return

    try:
        cur = conn.cursor()

        # Verificar si ya existe el contexto en la base de datos
        cur.execute("""
            SELECT context_uuid FROM public.dialplan
            WHERE tenant_uuid = ? AND context_name = ?
        """, (tenant_uuid, context_name))
        result = cur.fetchone()

        if result:
            # Actualizar XML si el contexto ya existe
            context_uuid = result[0]
            cur.execute("""
                UPDATE public.dialplan
                SET xml_data = ?, expression = ?
                WHERE context_uuid = ?
            """, (xml_data, expression, context_uuid))
            logging.info(f"Dialplan {context_name} actualizado correctamente.")
        else:
            # Insertar nuevo contexto
            context_uuid = str(uuid.uuid4())
            cur.execute("""
                INSERT INTO public.dialplan (
                    context_uuid, tenant_uuid, context_name, expression, xml_data, insert_user
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (context_uuid, tenant_uuid, context_name, expression, xml_data, None))
            logging.info(f"Dialplan {context_name} insertado correctamente.")

        conn.commit()
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
                    insert_or_update_dialplan(conn, tenant_uuid, ext["context_name"], ext["expression"], ext["xml_data"])

    conn.close()
    logging.info("✅ Migración de dialplan completada.")

if __name__ == "__main__":
    migrate_dialplan()
