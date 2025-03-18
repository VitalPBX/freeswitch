import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid

# ODBC Data Source Name (DSN) definido en /etc/odbc.ini
ODBC_DSN = "ring2all"
SIP_PROFILES_DIR = "/etc/freeswitch/sip_profiles"

def connect_db():
    conn = pyodbc.connect(f"DSN={ODBC_DSN}")
    return conn

def extract_and_format_settings(file_path):
    """
    Lee un archivo XML, extrae solo la sección <settings>, elimina comentarios y la formatea.
    Retorna el XML de settings como string.
    """
    try:
        # Parsear el XML sin comentarios
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=False, insert_pis=False))
        tree = ET.parse(file_path, parser=parser)
        root = tree.getroot()

        # Extraer solo la sección <settings>
        settings_section = root.find("settings")
        if settings_section is None:
            raise ValueError("No se encontró la sección <settings> en el archivo")

        # Convertir a string con formato limpio
        xml_string = ET.tostring(settings_section, encoding='utf-8', method='xml').decode('utf-8')
        
        # Formatear con tabulación usando minidom
        from xml.dom import minidom
        pretty_xml = minidom.parseString(xml_string).toprettyxml(indent="  ")
        
        # Eliminar líneas vacías y la declaración <?xml>
        lines = [line for line in pretty_xml.splitlines() if line.strip()]
        formatted_xml = "\n".join(lines[1:])  # Saltar la primera línea (<?xml ...?>)
        
        return formatted_xml
    except Exception as e:
        print(f"⚠️ Error procesando {file_path}: {e}")
        return None

def migrate_profiles():
    conn = connect_db()
    cursor = conn.cursor()
    
    # Leer los perfiles XML
    for file_name in os.listdir(SIP_PROFILES_DIR):
        file_path = os.path.join(SIP_PROFILES_DIR, file_name)
        if not os.path.isfile(file_path) or not file_path.endswith(".xml"):
            continue
        
        print(f"🔹 Migrando perfil SIP: {file_name}")
        
        # Obtener el nombre del perfil y el XML de <settings>
        tree = ET.parse(file_path)
        root = tree.getroot()
        profile_name = root.get("name")
        xml_data = extract_and_format_settings(file_path)
        
        if not profile_name or not xml_data:
            print(f"⚠️ No se pudo procesar {file_name}")
            continue
        
        # Generar un UUID para el perfil
        profile_uuid = str(uuid.uuid4())
        
        # Insertar en la tabla sip_profiles
        cursor.execute("""
            INSERT INTO public.sip_profiles (profile_uuid, profile_name, xml_data, enabled, insert_date)
            VALUES (?, ?, ?, ?, ?)
        """, (profile_uuid, profile_name, xml_data, True, 'NOW()'))
        
        print(f"✅ Perfil {profile_name} migrado con UUID: {profile_uuid}")
    
    conn.commit()
    cursor.close()
    conn.close()
    print("✅ Migración completada.")

if __name__ == "__main__":
    migrate_profiles()
