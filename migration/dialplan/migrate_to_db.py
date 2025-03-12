#!/usr/bin/env python3

import psycopg2
import os
import xml.etree.ElementTree as ET
import uuid
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

db_config = {
    "dbname": "$r2a_database",
    "user": "$r2l_user",
    "password": "$r2a_password",
    "host": "localhost",
    "port": "5432"
}

DIALPLAN_DIR = "/etc/freeswitch/dialplan"
IVR_MENU_DIR = "/etc/freeswitch/ivr_menus"
DEFAULT_TENANT_NAME = "Default"

def connect_db():
    try:
        conn = psycopg2.connect(**db_config)
        logging.info("Database connection established.")
        return conn
    except Exception as e:
        logging.error(f"Error connecting to database: {e}")
        raise

def ensure_unique_constraint(conn):
    try:
        with conn.cursor() as cur:
            cur.execute("""
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM pg_constraint
                        WHERE conname = 'dialplan_contexts_context_name_key'
                        AND contype = 'u'
                    ) THEN
                        ALTER TABLE public.dialplan_contexts
                        ADD CONSTRAINT dialplan_contexts_context_name_key UNIQUE (context_name);
                    END IF;
                END;
                $$;
            """)
            conn.commit()
            logging.info("Unique constraint on context_name ensured.")
            return True
    except Exception as e:
        conn.rollback()
        logging.warning(f"Could not ensure unique constraint due to: {e}. Proceeding without it.")
        return False

def get_default_tenant_uuid(conn):
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = %s;", (DEFAULT_TENANT_NAME,))
            result = cur.fetchone()
            if result:
                logging.info(f"Found default tenant '{DEFAULT_TENANT_NAME}' with UUID: {result[0]}")
                return result[0]
            else:
                raise Exception(f"No tenant found with name '{DEFAULT_TENANT_NAME}' in table 'tenants'.")
    except Exception as e:
        logging.error(f"Error retrieving default tenant UUID: {e}")
        raise

def delete_dialplan_data(conn):
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM public.dialplan_actions;")
            cur.execute("DELETE FROM public.dialplan_conditions;")
            cur.execute("DELETE FROM public.dialplan_extensions;")
            cur.execute("DELETE FROM public.dialplan_contexts;")
            conn.commit()
            logging.info("All dialplan data deleted successfully.")
    except Exception as e:
        conn.rollback()
        logging.error(f"Error deleting data: {e}")
        raise

def get_or_insert_context(conn, context_name, tenant_uuid):
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT context_uuid FROM public.dialplan_contexts WHERE context_name = %s;", (context_name,))
            result = cur.fetchone()
            if result:
                logging.info(f"Context '{context_name}' already exists with UUID: {result[0]}")
                return result[0]
            
            context_uuid = str(uuid.uuid4())
            cur.execute("""
                INSERT INTO public.dialplan_contexts (context_uuid, tenant_uuid, context_name)
                VALUES (%s, %s, %s)
                RETURNING context_uuid;
            """, (context_uuid, tenant_uuid, context_name))
            result = cur.fetchone()
            conn.commit()
            logging.info(f"Context '{context_name}' inserted with UUID: {result[0]}")
            return result[0]
    except Exception as e:
        conn.rollback()
        logging.error(f"Error getting or inserting context '{context_name}': {e}")
        raise

def insert_extension(conn, context_uuid, extension_name, continue_val, priority=1):
    extension_uuid = str(uuid.uuid4())
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO public.dialplan_extensions (extension_uuid, context_uuid, extension_name, continue, priority)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING extension_uuid;
            """, (extension_uuid, context_uuid, extension_name, continue_val, priority))
            result = cur.fetchone()
            conn.commit()
            logging.info(f"Extension '{extension_name}' inserted with UUID: {result[0]}")
            return result[0]
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting extension '{extension_name}': {e}")
        raise

def insert_condition(conn, extension_uuid, field, expression, break_on_match, condition_order=1):
    condition_uuid = str(uuid.uuid4())
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO public.dialplan_conditions (condition_uuid, extension_uuid, field, expression, break_on_match, condition_order)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING condition_uuid;
            """, (condition_uuid, extension_uuid, field, expression, break_on_match, condition_order))
            result = cur.fetchone()
            conn.commit()
            logging.info(f"Condition inserted for extension UUID '{extension_uuid}' with UUID: {result[0]}")
            return result[0]
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting condition: {e}")
        raise

def insert_action(conn, condition_uuid, action_type, application, data, action_order):
    action_uuid = str(uuid.uuid4())
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO public.dialplan_actions (action_uuid, condition_uuid, action_type, application, data, action_order)
                VALUES (%s, %s, %s, %s, %s, %s);
            """, (action_uuid, condition_uuid, action_type, application, data, action_order))
            conn.commit()
            logging.info(f"Action '{application}' inserted for condition UUID '{condition_uuid}'")
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting action '{application}': {e}")
        raise

def migrate_dialplan(conn, tenant_uuid, directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.xml'):
                file_path = os.path.join(root, file)
                logging.info(f"Processing file: {file_path}")
                try:
                    tree = ET.parse(file_path)
                    xml_root = tree.getroot()

                    context_name = xml_root.get('name', 'default')
                    context_uuid = get_or_insert_context(conn, context_name, tenant_uuid)

                    for extension in xml_root.findall('.//extension'):
                        extension_name = extension.get('name', 'unnamed')
                        continue_val = extension.get('continue', 'false') == 'true'
                        extension_uuid = insert_extension(conn, context_uuid, extension_name, continue_val)

                        condition_order = 1
                        for condition in extension.findall('condition'):
                            field = condition.get('field', '')
                            expression = condition.get('expression', '')
                            break_on_match = condition.get('break', 'on-false')
                            condition_uuid = insert_condition(conn, extension_uuid, field, expression, break_on_match, condition_order)
                            condition_order += 1

                            action_order = 1
                            for action in condition.findall('action'):
                                application = action.get('application', '')
                                data = action.get('data', '')
                                insert_action(conn, condition_uuid, 'action', application, data, action_order)
                                action_order += 1

                except Exception as e:
                    logging.error(f"Error processing {file_path}: {e}")

def migrate_ivr_menus(conn, tenant_uuid, directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.xml'):
                file_path = os.path.join(root, file)
                logging.info(f"Processing IVR menu: {file_path}")
                try:
                    tree = ET.parse(file_path)
                    xml_root = tree.getroot()

                    ivr_name = xml_root.get('name', 'unnamed_ivr')
                    context_uuid = get_or_insert_context(conn, 'default', tenant_uuid)
                    extension_uuid = insert_extension(conn, context_uuid, ivr_name, False)

                    condition_uuid = insert_condition(conn, extension_uuid, 'destination_number', f'^{ivr_name}$', 'on-false', 1)
                    insert_action(conn, condition_uuid, 'action', 'ivr', ivr_name, 1)

                except Exception as e:
                    logging.error(f"Error processing IVR menu {file_path}: {e}")

def main():
    conn = None
    try:
        conn = connect_db()
        ensure_unique_constraint(conn)
        tenant_uuid = get_default_tenant_uuid(conn)
        delete_dialplan_data(conn)
        migrate_dialplan(conn, tenant_uuid, DIALPLAN_DIR)
        migrate_ivr_menus(conn, tenant_uuid, IVR_MENU_DIR)
        logging.info("Migration completed successfully.")
    except Exception as e:
        logging.error(f"Error in migration process: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("Database connection closed.")

if __name__ == "__main__":
    main()
