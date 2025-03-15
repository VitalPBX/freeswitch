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

def parse_sip_profile(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        profile_name = root.get("name")
        settings = []
        gateways = []
        
        # Extraer configuraciones
        settings_section = root.find("settings")
        if settings_section:
            for param in settings_section.findall("param"):
                name = param.get("name")
                value = param.get("value")
                settings.append((name, value))
        
        # Extraer gateways
        gateways_section = root.find("gateways")
        if gateways_section:
            for gateway in gateways_section.findall("gateway"):
                gateway_name = gateway.get("name")
                gateways.append(gateway_name)
        
        return profile_name, settings, gateways
    except Exception as e:
        print(f"⚠️ Error procesando {file_path}: {e}")
        return None, None, None

def migrate_profiles():
    conn = connect_db()
    cursor = conn.cursor()
    
    # Leer los perfiles XML
    for file_name in os.listdir(SIP_PROFILES_DIR):
        file_path = os.path.join(SIP_PROFILES_DIR, file_name)
        if not os.path.isfile(file_path) or not file_path.endswith(".xml"):
            continue
        
        profile_name, settings, gateways = parse_sip_profile(file_path)
        if not profile_name:
            print(f"⚠️ No se pudo procesar {file_name}")
            continue
        
        print(f"🔹 Migrando perfil SIP: {profile_name}")
        profile_uuid = str(uuid.uuid4())
        
        # Insertar perfil en la base de datos
        cursor.execute(
            "INSERT INTO sip_profiles (profile_uuid, profile_name) VALUES (?, ?)",
            (profile_uuid, profile_name)
        )
        
        # Insertar configuraciones
        for name, value in settings:
            setting_uuid = str(uuid.uuid4())
            cursor.execute(
                "INSERT INTO sip_profile_settings (setting_uuid, profile_uuid, name, value) VALUES (?, ?, ?, ?)",
                (setting_uuid, profile_uuid, name, value)
            )
        
        # Insertar gateways
        for gateway_name in gateways:
            gateway_uuid = str(uuid.uuid4())
            cursor.execute(
                "INSERT INTO sip_profile_gateways (gateway_uuid, profile_uuid, gateway_name) VALUES (?, ?, ?)",
                (gateway_uuid, profile_uuid, gateway_name)
            )
    
    conn.commit()
    cursor.close()
    conn.close()
    print("✅ Migración completada.")

if __name__ == "__main__":
    migrate_profiles()
