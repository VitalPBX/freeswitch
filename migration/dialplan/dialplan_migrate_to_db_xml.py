#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid
import logging
import re
import xml.sax.saxutils as saxutils

# Configuración del logging (guardar en archivo y mostrar en pantalla)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration_dialplan.log'),
        logging.StreamHandler()  # Muestra en pantalla
    ]
)

# ODBC Data Source Name (DSN) definido en /etc/odbc.ini
ODBC_DSN = "ring2all"

# Directorios de los archivos XML
DIALPLAN_DIR = "/etc/freeswitch/dialplan"
IVR_MENUS_DIR = "/etc/freeswitch/ivr_menus"

# Tenant por defecto
DEFAULT_TENANT_NAME = "Default"

def connect_db():
    """Establece la conexión con la base de datos."""
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error conectando a la base de datos: {e}")
        raise

def clean_xml(xml_str, remove_include=True):
    """Elimina comentarios, la etiqueta <include> (si se indica), y formatea el XML con tabulación correcta."""
    try:
        # Eliminar comentarios manualmente antes de parsear
        xml_str = re.sub(r'<!--[\s\S]*?-->', '', xml_str)
        xml_str = xml_str.strip()
        if xml_str.startswith('\ufeff'):
            xml_str = xml_str[1:]
        if not xml_str:
            raise ValueError("XML está vacío después de eliminar comentarios")

        # Parsear el XML
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=False, insert_pis=False))
        root = ET.fromstring(xml_str, parser=parser)

        # Si remove_include es True, extraer el contenido dentro de <include>
        if remove_include and root.tag == "include":
            root = root[0]  # Tomar el primer hijo (por ejemplo, <context> o <menu>)

        # Construir el XML manualmente con tabulación precisa
        def build_xml(elem, level=0):
            indent_str = "\t" * level
            lines = []

            # Determinar si la etiqueta debe ser autocerrada
            is_self_closing = elem.tag in ["action", "anti-action"] and not elem.text and not len(elem)

            # Apertura de la etiqueta con atributos escapados
            attrs = " ".join(f'{k}="{saxutils.escape(v)}"' for k, v in elem.attrib.items())
            if is_self_closing:
                lines.append(f"{indent_str}<{elem.tag}{' ' + attrs if attrs else ''}/>")
            else:
                lines.append(f"{indent_str}<{elem.tag}{' ' + attrs if attrs else ''}>")

                # Contenido de texto (si existe y no es solo espacios)
                if elem.text and elem.text.strip():
                    lines.append(f"{indent_str}\t{saxutils.escape(elem.text.strip())}")

                # Hijos
                for child in elem:
                    lines.extend(build_xml(child, level + 1))

                # Cierre de la etiqueta (solo si no es autocerrada)
                lines.append(f"{indent_str}</{elem.tag}>")

            return lines

        xml_lines = build_xml(root, 0)
        formatted_xml = "\n".join(xml_lines)

        # Validar el XML generado
        try:
            ET.fromstring(formatted_xml)
        except ET.ParseError as e:
            logging.error(f"❌ XML generado inválido: {e}\nXML:\n{formatted_xml}")
            return None

        return formatted_xml
    except ET.ParseError as e:
        logging.error(f"❌ Error de sintaxis en XML original: {e}")
        return None
    except ValueError as e:
        logging.error(f"❌ {e}")
        return None
    except Exception as e:
        logging.error(f"❌ Error formateando XML: {e}")
        return None

def get_tenant_uuid(conn):
    """Obtiene el UUID del tenant por defecto."""
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

def process_dialplan(file_path):
    """Procesa un archivo XML de dialplan y extrae cada <extension> como entrada independiente."""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            xml_str = f.read()

        # Eliminar comentarios iniciales antes de parsear
        xml_str = re.sub(r'<!--[\s\S]*?-->', '', xml_str)
        xml_str = xml_str.strip()
        if not xml_str:
            logging.error(f"❌ Archivo vacío después de eliminar comentarios: {file_path}")
            return None, []

        # Parsear el XML completo
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=False, insert_pis=False))
        root = ET.fromstring(xml_str, parser=parser)

        # Si hay <include>, tomar el contenido interno
        if root.tag == "include":
            root = root[0]  # Tomar <context>

        context_name = root.get("name", "default")
        extensions = []

        for extension in root.findall(".//extension"):
            extension_name = extension.get("name", "unnamed")

            # Construir el XML de la extensión manualmente con condiciones anidadas
            def build_extension_xml(elem, level=0):
                indent_str = "\t" * level
                lines = []

                # Apertura de la extensión
                attrs = " ".join(f'{k}="{saxutils.escape(v)}"' for k, v in elem.attrib.items())
                lines.append(f"{indent_str}<{elem.tag}{' ' + attrs if attrs else ''}>")

                # Procesar condiciones anidadas
                conditions = elem.findall("condition")
                if conditions:
                    current_level = level + 1
                    for i, condition in enumerate(conditions):
                        cond_indent = indent_str + "\t" * current_level
                        cond_attrs = " ".join(f'{k}="{saxutils.escape(v)}"' for k, v in condition.attrib.items())
                        lines.append(f"{cond_indent}<condition{' ' + cond_attrs if cond_attrs else ''}>")

                        # Acciones dentro de la condición
                        for action in condition.findall("action"):
                            action_indent = cond_indent + "\t"
                            action_attrs = " ".join(f'{k}="{saxutils.escape(v)}"' for k, v in action.attrib.items())
                            lines.append(f"{action_indent}<action{' ' + action_attrs if action_attrs else ''}/>")

                        # Anti-acciones dentro de la condición
                        for anti_action in condition.findall("anti-action"):
                            anti_indent = cond_indent + "\t"
                            anti_attrs = " ".join(f'{k}="{saxutils.escape(v)}"' for k, v in anti_action.attrib.items())
                            lines.append(f"{anti_indent}<anti-action{' ' + anti_attrs if anti_attrs else ''}/>")

                        # Anidar la siguiente condición si existe
                        if i < len(conditions) - 1:
                            current_level += 1
                        else:
                            # Cerrar todas las condiciones abiertas
                            for j in range(current_level - level, 0, -1):
                                close_indent = indent_str + "\t" * j
                                lines.append(f"{close_indent}</condition>")

                lines.append(f"{indent_str}</{elem.tag}>")
                return lines

            extension_xml_lines = build_extension_xml(extension, 0)
            extension_xml = "\n".join(extension_xml_lines)

            if extension_xml is None:
                logging.error(f"❌ Error generando XML para extensión '{extension_name}' en {file_path}")
                continue

            # Obtener la primera condición para la expresión
            condition = extension.find(".//condition")
            expression = condition.get("expression", "") if condition is not None else ""
            expression_clean = expression.strip("^$")  # Limpiar ^ y $

            extensions.append({
                "context_name": context_name,
                "description": f"Extension {extension_name} from {os.path.basename(file_path)}",
                "expression": expression_clean,
                "xml_data": extension_xml
            })

        logging.info(f"🔹 Procesado contexto: {context_name} con {len(extensions)} extensiones desde {file_path}")
        return context_name, extensions
    except ET.ParseError as e:
        logging.error(f"❌ Error de sintaxis en XML: {e} en {file_path}")
        return None, []
    except Exception as e:
        logging.error(f"❌ Error procesando {file_path}: {e}")
        return None, []

def insert_or_update_dialplan(conn, tenant_uuid, context_name, name, description, expression, xml_data):
    """Inserta o actualiza una entrada en la tabla `dialplan`, incluyendo el campo `name`."""
    if not xml_data:
        logging.warning(f"⚠️ XML vacío para {context_name}. No se insertará.")
        return

    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO core.dialplan (
                context_uuid, tenant_uuid, context_name, name, description, expression, xml_data, enabled, insert_user
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (str(uuid.uuid4()), tenant_uuid, context_name, name, description, expression, xml_data, True, None))
        conn.commit()
        cur.close()
        logging.info(f"✅ Extensión '{name}' en contexto '{context_name}' insertada correctamente.")
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error insertando/actualizando {context_name}: {e}")
        raise

def process_dialplan(file_path):
    # ... (sin cambios hasta)

            extensions.append({
                "context_name": context_name,
                "name": extension_name,
                "description": f"Extension {extension_name} from {os.path.basename(file_path)}",
                "expression": expression_clean,
                "xml_data": extension_xml
            })

    # ...

def migrate_dialplan():
    logging.info("🌟 Iniciando proceso de migración de dialplan...")
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)

    logging.info(f"🚀 Iniciando migración desde {DIALPLAN_DIR}")
    for root_dir, _, files in os.walk(DIALPLAN_DIR):
        for file in files:
            if file.endswith(".xml"):
                file_path = os.path.join(root_dir, file)
                context_name, extensions = process_dialplan(file_path)
                if context_name:
                    for ext in extensions:
                        insert_or_update_dialplan(
                            conn, tenant_uuid,
                            ext["context_name"],
                            ext["name"],
                            ext["description"],
                            ext["expression"],
                            ext["xml_data"]
                        )

    logging.info("🏁 Migración de dialplan completada.")
    conn.close()
    logging.info("🔒 Conexión a la base de datos cerrada.")

def migrate_ivr_menus():
    """Lee archivos XML de IVR y los inserta en la base de datos."""
    logging.info("🌟 Iniciando proceso de migración de IVR...")
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)

    logging.info(f"🚀 Iniciando migración desde {IVR_MENUS_DIR}")
    for root_dir, _, files in os.walk(IVR_MENUS_DIR):
        for file in files:
            if file.endswith(".xml"):
                file_path = os.path.join(root_dir, file)
                with open(file_path, "r", encoding="utf-8") as f:
                    xml_data = clean_xml(f.read(), remove_include=True)  # Eliminar <include>

                if xml_data is None:
                    logging.error(f"❌ XML inválido o vacío en archivo: {file_path}")
                    continue

                root = ET.fromstring(xml_data)
                ivr_name = root.get("name", "Unnamed IVR")

                try:
                    cur = conn.cursor()
                    cur.execute("""
                        INSERT INTO core.ivr_menus (
                            ivr_uuid, tenant_uuid, ivr_name, xml_data, insert_user
                        ) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT (tenant_uuid, ivr_name) 
                        DO UPDATE SET xml_data = EXCLUDED.xml_data
                    """, (str(uuid.uuid4()), tenant_uuid, ivr_name, xml_data, None))

                    conn.commit()

                    ivr_uuid = cur.execute("SELECT ivr_uuid FROM core.ivr_menus WHERE ivr_name = ?", (ivr_name,)).fetchone()[0]
                    cur.execute("DELETE FROM core.ivr_menu_options WHERE ivr_uuid = ?", (ivr_uuid,))

                    for entry in root.findall(".//entry"):
                        digits = entry.get("digits", "")
                        action = entry.get("action", "")
                        param = entry.get("param", "")

                        cur.execute("""
                            INSERT INTO core.ivr_menu_options (option_uuid, ivr_uuid, digits, action, param)
                            VALUES (?, ?, ?, ?, ?)
                        """, (str(uuid.uuid4()), ivr_uuid, digits, action, param))

                    conn.commit()
                    logging.info(f"✅ IVR '{ivr_name}' y sus opciones insertados/actualizados desde {file_path}")
                    cur.close()
                except Exception as e:
                    conn.rollback()
                    logging.error(f"❌ Error insertando/actualizando IVR '{ivr_name}': {e}")
                    raise

    logging.info("🏁 Migración de IVR completada.")
    conn.close()
    logging.info("🔒 Conexión a la base de datos cerrada.")

if __name__ == "__main__":
    migrate_dialplan()
    migrate_ivr_menus()
