#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid
import logging

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration_blacklist.log'),
        logging.StreamHandler()
    ]
)

# Configuraciones
ODBC_DSN = "ring2all"
BLACKLIST_DIR = "/etc/freeswitch/blacklist"
DEFAULT_TENANT_NAME = "Default"

# Conexión DB
def connect_db():
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error conectando a la base de datos: {e}")
        raise

# Obtener UUID del tenant
def get_tenant_uuid(conn):
    cur = conn.cursor()
    cur.execute("SELECT tenant_uuid FROM tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
    result = cur.fetchone()
    cur.close()
    if result:
        return result[0]
    else:
        raise Exception("Tenant 'Default' no encontrado.")

# Procesar archivo de blacklist (asumiendo .txt o .csv simple)
def process_blacklist_file(file_path):
    entries = []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            number = line.strip()
            if number:
                entries.append(number)
    return entries

# Insertar entrada en DB
def insert_blacklist(conn, tenant_uuid, phone_number):
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO core.blacklist (
                blacklist_uuid, tenant_uuid, phone_number
            ) VALUES (?, ?, ?)
            ON CONFLICT (tenant_uuid, phone_number)
            DO NOTHING
        """, (
            str(uuid.uuid4()), tenant_uuid, phone_number
        ))
        conn.commit()
        cur.close()
        logging.info(f"✅ Insertado: {phone_number}")
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error insertando {phone_number}: {e}")

# Migración principal
def migrate_blacklist():
    logging.info("🚀 Iniciando migración de blacklist...")
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)

    for root_dir, _, files in os.walk(BLACKLIST_DIR):
        for file in files:
            if file.endswith(".txt") or file.endswith(".csv"):
                file_path = os.path.join(root_dir, file)
                logging.info(f"📄 Procesando archivo: {file_path}")
                entries = process_blacklist_file(file_path)
                for number in entries:
                    insert_blacklist(conn, tenant_uuid, number)

    conn.close()
    logging.info("🏁 Migración de blacklist completada.")

if __name__ == "__main__":
    migrate_blacklist()
