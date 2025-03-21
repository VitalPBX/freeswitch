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

# Configuraciones
ODBC_DSN = "ring2all"
DEFAULT_TENANT_NAME = "Default"
CALLCENTER_DIR = "/etc/freeswitch/autoload_configs"


def connect_db():
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error conectando a la base de datos: {e}")
        raise


def get_tenant_uuid(conn):
    try:
        cur = conn.cursor()
        cur.execute("SELECT tenant_uuid FROM tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
        result = cur.fetchone()
        cur.close()
        if result:
            return result[0]
        raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")
    except Exception as e:
        logging.error(f"❌ Error obteniendo UUID del tenant: {e}")
        raise


def process_callcenter_config(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        queues = []
        agents = []
        tiers = []

        for queue in root.findall("./queues/queue"):
            queues.append({
                "name": queue.get("name"),
                "strategy": queue.get("strategy", "longest-idle-agent"),
                "moh_sound": queue.get("music-on-hold", "default"),
                "max_wait_time": int(queue.get("max-wait-time", 0)),
                "record_template": queue.get("record-template"),
            })

        for agent in root.findall("./agents/agent"):
            agents.append({
                "name": agent.get("name"),
                "type": agent.get("type", "callback"),
                "contact": agent.get("contact"),
                "status": agent.get("status", "Available"),
                "max_no_answer": int(agent.get("max-no-answer", 3)),
                "wrap_up_time": int(agent.get("wrap-up-time", 10)),
                "reject_delay_time": int(agent.get("reject-delay-time", 10)),
                "busy_delay_time": int(agent.get("busy-delay-time", 10))
            })

        for tier in root.findall("./tiers/tier"):
            tiers.append({
                "queue_name": tier.get("queue"),
                "agent_name": tier.get("agent"),
                "level": int(tier.get("level", 1)),
                "position": int(tier.get("position", 1))
            })

        return queues, agents, tiers

    except Exception as e:
        logging.error(f"❌ Error procesando {file_path}: {e}")
        return [], [], []


def insert_data(conn, tenant_uuid, queues, agents, tiers):
    try:
        cur = conn.cursor()

        queue_map = {}
        agent_map = {}

        for q in queues:
            q_uuid = str(uuid.uuid4())
            queue_map[q["name"]] = q_uuid
            cur.execute("""
                INSERT INTO core.callcenter_queues (
                    queue_uuid, tenant_uuid, name, strategy, moh_sound, max_wait_time, record_template
                ) VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (q_uuid, tenant_uuid, q["name"], q["strategy"], q["moh_sound"], q["max_wait_time"], q["record_template"])
            )

        for a in agents:
            a_uuid = str(uuid.uuid4())
            agent_map[a["name"]] = a_uuid
            cur.execute("""
                INSERT INTO core.callcenter_agents (
                    agent_uuid, tenant_uuid, name, type, contact, status, max_no_answer, wrap_up_time,
                    reject_delay_time, busy_delay_time
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (a_uuid, tenant_uuid, a["name"], a["type"], a["contact"], a["status"], a["max_no_answer"],
                 a["wrap_up_time"], a["reject_delay_time"], a["busy_delay_time"])
            )

        for t in tiers:
            cur.execute("""
                INSERT INTO core.callcenter_tiers (
                    tier_uuid, tenant_uuid, queue_uuid, agent_uuid, level, position
                ) VALUES (?, ?, ?, ?, ?, ?)""",
                (str(uuid.uuid4()), tenant_uuid, queue_map.get(t["queue_name"]), agent_map.get(t["agent_name"]),
                 t["level"], t["position"])
            )

        conn.commit()
        cur.close()
        logging.info("✅ Datos de Call Center insertados correctamente.")
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error insertando datos de Call Center: {e}")
        raise


def main():
    logging.info("🌟 Iniciando migración de configuración de Call Center...")
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)

    for root_dir, _, files in os.walk(CALLCENTER_DIR):
        for file in files:
            if file == "callcenter.conf.xml":
                file_path = os.path.join(root_dir, file)
                queues, agents, tiers = process_callcenter_config(file_path)
                insert_data(conn, tenant_uuid, queues, agents, tiers)

    conn.close()
    logging.info("🔒 Conexión cerrada. Migración finalizada.")


if __name__ == "__main__":
    main()
