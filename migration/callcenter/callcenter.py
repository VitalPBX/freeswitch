#!/usr/bin/env python3

import os
import xml.etree.ElementTree as ET
import pyodbc
import uuid
import logging

# Configuración del logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration_callcenter.log'),
        logging.StreamHandler()
    ]
)

# DSN y directorio de configuración
ODBC_DSN = "ring2all"
CALLCENTER_CONF = "/etc/freeswitch/autoload_configs/callcenter.conf.xml"
DEFAULT_TENANT_NAME = "Default"


def connect_db():
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error conectando a la base de datos: {e}")
        raise


def get_tenant_uuid(conn):
    cur = conn.cursor()
    cur.execute("SELECT tenant_uuid FROM tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
    result = cur.fetchone()
    cur.close()
    if result:
        return result[0]
    raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")


def parse_callcenter_xml(path):
    try:
        tree = ET.parse(path)
        root = tree.getroot()
        queues = root.findall(".//queue")
        agents = root.findall(".//agent")
        tiers = root.findall(".//tier")
        return queues, agents, tiers
    except Exception as e:
        logging.error(f"❌ Error procesando XML {path}: {e}")
        raise


def insert_queue(conn, tenant_uuid, queue):
    name = queue.get("name")
    strategy = queue.get("strategy")
    moh_sound = queue.get("moh-sound")
    record_template = queue.get("record-template")
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO core.callcenter_queues (
            queue_uuid, tenant_uuid, name, strategy, moh_sound, record_template
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (tenant_uuid, name) DO UPDATE SET
            strategy = EXCLUDED.strategy,
            moh_sound = EXCLUDED.moh_sound,
            record_template = EXCLUDED.record_template
    """, (
        str(uuid.uuid4()), tenant_uuid, name, strategy, moh_sound, record_template
    ))
    cur.close()


def insert_agent(conn, tenant_uuid, agent):
    name = agent.get("name")
    contact = agent.get("contact")
    type_ = agent.get("type")
    status = agent.get("status")
    max_no_answer = agent.get("max-no-answer")
    wrap_up_time = agent.get("wrap-up-time")
    reject_delay_time = agent.get("reject-delay-time")
    busy_delay_time = agent.get("busy-delay-time")
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO core.callcenter_agents (
            agent_uuid, tenant_uuid, name, contact, type, status,
            max_no_answer, wrap_up_time, reject_delay_time, busy_delay_time
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (tenant_uuid, name) DO UPDATE SET
            contact = EXCLUDED.contact,
            type = EXCLUDED.type,
            status = EXCLUDED.status,
            max_no_answer = EXCLUDED.max_no_answer,
            wrap_up_time = EXCLUDED.wrap_up_time,
            reject_delay_time = EXCLUDED.reject_delay_time,
            busy_delay_time = EXCLUDED.busy_delay_time
    """, (
        str(uuid.uuid4()), tenant_uuid, name, contact, type_, status,
        max_no_answer, wrap_up_time, reject_delay_time, busy_delay_time
    ))
    cur.close()


def insert_tier(conn, tenant_uuid, tier):
    queue = tier.get("queue")
    agent = tier.get("agent")
    level = int(tier.get("level", 1))
    position = int(tier.get("position", 1))
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO core.callcenter_tiers (
            tier_uuid, tenant_uuid, queue_name, agent_name, level, position
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (tenant_uuid, queue_name, agent_name) DO UPDATE SET
            level = EXCLUDED.level,
            position = EXCLUDED.position
    """, (
        str(uuid.uuid4()), tenant_uuid, queue, agent, level, position
    ))
    cur.close()


def migrate_callcenter():
    logging.info("🌟 Iniciando migración del call center...")
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)
    queues, agents, tiers = parse_callcenter_xml(CALLCENTER_CONF)

    for queue in queues:
        insert_queue(conn, tenant_uuid, queue)
    for agent in agents:
        insert_agent(conn, tenant_uuid, agent)
    for tier in tiers:
        insert_tier(conn, tenant_uuid, tier)

    conn.commit()
    conn.close()
    logging.info("✅ Migración de call center completada correctamente.")


if __name__ == "__main__":
    migrate_callcenter()
