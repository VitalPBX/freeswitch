#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import logging
import uuid
import re
from xml.dom.minidom import parseString

# Configuración del log
logging.basicConfig(
    filename='migration_dialplan.log',
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Configuración de conexión a la base de datos
ODBC_DSN = "ring2all"
DIALPLAN_DIR = "/etc/freeswitch/dialplan/"  # Ajusta la ruta si es necesario
DEFAULT_TENANT_NAME = "Default"

# Definición de categorías para los dialplans
CATEGORY_MAPPING = {
    "features": "Feature Codes",
    "public": "Public Dialplan",
    "default": "Default Routing",
    "skinny-patterns": "Skinny Patterns",
}

def connect_db():
    """Establece la conexión a la base de datos utilizando ODBC."""
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("Conexión a la base de datos establecida.")
        return conn
    except Exception as e:
        logging.error(f"Error de conexión a la base de datos: {e}")
        raise

def get_tenant_uuid(conn):
    """Obtiene el UUID del tenant 'Default'."""
    try:
        cur = conn.cursor()
        cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
        result = cur.fetchone()
        cur.close()
        if result:
            logging.info(f"Tenant '{DEFAULT_TENANT_NAME}' encontrado con UUID: {result[0]}")
            return result[0]
        else:
            raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")
    except Exception as e:
        logging.error(f"Error obteniendo el UUID del tenant: {e}")
        raise

def clean_expression(expression):
    """Limpia la expresión eliminando ^ y $ al inicio y final."""
    if expression:
        return re.sub(r'^\^|\$$', '', expression)
    return None

def format_xml(element):
    """Corrige la justificación del XML asegurando alineación de <extension>."""
    try:
        raw_xml = ET.tostring(element, encoding='unicode')
        parsed_xml = parseString(raw_xml)  # Analiza la estructura XML
        formatted_xml = parsed_xml.toprettyxml(indent="    ")  # Aplica indentación de 4 espacios
        
        # Eliminar líneas vacías adicionales que pueden agregarse con `toprettyxml`
        formatted_xml = "\n".join([line for line in formatted_xml.split("\n") if line.strip()])
        
        return formatted_xml
    except Exception as e:
        logging.error(f"Error formateando XML: {e}")
        return ET.tostring(element, encoding='unicode').strip()  # Devuelve el XML sin formato en caso de error

def process_dialplan_xml(file_path):
    """Extrae las extensiones de un archivo XML del dialplan."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        extensions = []
        
        # Obtener el nombre del contexto
        context_element = root.find(".//context")
        context_name = context_element.get("name") if context_element is not None else "default"

        # Determinar la categoría basada en el nombre del archivo o contexto
        category = CATEGORY_MAPPING.get(context_name, "Uncategorized")

        # Extraer cada extensión
        for extension in root.findall(".//extension"):
            ext_name = extension.get("name", "unknown")
            conditions = extension.findall("condition")
            expression = None
            
            # Extraer la primera expresión encontrada y limpiarla
            for condition in conditions:
                raw_expression = condition.get("expression")
                if raw_expression:
                    expression = clean_expression(raw_expression)
                    break  

            # Convertir XML de la extensión a texto con formato corregido
            extension_xml = format_xml(extension)

            # Asegurar que <extension> está alineado correctamente
            if not extension_xml.startswith("<extension"):
                extension_xml = "<extension" + extension_xml.split("<extension", 1)[1]

            # Determinar si está habilitado
            enabled = True  # Por defecto habilitado, se puede mejorar con más lógica

            extensions.append({
                "context": context_name,
                "name": ext_name,
                "expression": expression,
                "xml_config": extension_xml,
                "enabled": enabled,
                "category": category
            })
        
        return extensions
    except Exception as e:
        logging.error(f"Error procesando {file_path}: {e}")
        return None

def insert_dialplan_rule(conn, tenant_uuid, context, ext_name, expression, xml_config, enabled, category):
    """Inserta una regla de dialplan en la base de datos."""
    try:
        cur = conn.cursor()
        rule_uuid = str(uuid.uuid4())  
        cur.execute("""
            INSERT INTO public.dialplan (
                rule_uuid, tenant_uuid, context, name, expression, xml_config, enabled, category, insert_date
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
            ON CONFLICT (name, context) 
            DO UPDATE SET 
                expression = EXCLUDED.expression,
                xml_config = EXCLUDED.xml_config,
                enabled = EXCLUDED.enabled,
                category = EXCLUDED.category,
                update_date = NOW();
        """, (rule_uuid, tenant_uuid, context, ext_name, expression, xml_config, enabled, category))
        
        conn.commit()
        logging.info(f"Regla de dialplan '{ext_name}' en contexto '{context}' insertada/actualizada correctamente.")
        cur.close()
    except Exception as e:
        conn.rollback()
        logging.error(f"Error insertando/actualizando regla de dialplan '{ext_name}': {e}")
        raise

def migrate_dialplans(conn, tenant_uuid):
    """Escanea la carpeta de dialplans y migra los datos extraídos a la base de datos."""
    for root, _, files in os.walk(DIALPLAN_DIR):  
        for filename in files:
            if filename.endswith(".xml"):
                file_path = os.path.join(root, filename)
                logging.info(f"Procesando archivo de dialplan: {file_path}")
                rules = process_dialplan_xml(file_path)
                
                if rules:
                    for rule in rules:
                        insert_dialplan_rule(
                            conn, tenant_uuid, rule["context"], rule["name"], rule["expression"], 
                            rule["xml_config"], rule["enabled"], rule["category"]
                        )

def main():
    """Ejecuta la migración del dialplan."""
    conn = None
    try:
        conn = connect_db()
        tenant_uuid = get_tenant_uuid(conn)
        migrate_dialplans(conn, tenant_uuid)
        logging.info("Migración del dialplan completada exitosamente.")
    except Exception as e:
        logging.error(f"Fallo en la migración del dialplan: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("Conexión a la base de datos cerrada.")

if __name__ == "__main__":
    main()
