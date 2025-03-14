#!/usr/bin/env python3

import pyodbc
import os
import xml.etree.ElementTree as ET
import uuid
import logging

# Configure logging to track script execution and errors
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# ODBC Data Source Name (DSN) defined in /etc/odbc.ini
ODBC_DSN = "ring2all"

# File directories for dialplans and IVR menus
DIALPLAN_DIR = "/etc/freeswitch/dialplan"
DEFAULT_TENANT_NAME = "Default"

def connect_db():
    """
    Establishes a connection to the database using ODBC.
    The connection parameters are defined in the system's ODBC configuration (odbc.ini).
    """
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("Database connection established using ODBC.")
        return conn
    except Exception as e:
        logging.error(f"Error connecting to database via ODBC: {e}")
        raise

def get_default_tenant_uuid(conn):
    """
    Retrieves the UUID of the default tenant from the database.
    If the tenant does not exist, it raises an error.
    """
    try:
        cur = conn.cursor()
        cur.execute("SELECT tenant_uuid FROM public.tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
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
    """
    Deletes all existing dialplan data from the database before inserting new records.
    This ensures that the migration starts with a clean slate.
    """
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM public.dialplan_actions;")
        cur.execute("DELETE FROM public.dialplan_conditions;")
        cur.execute("DELETE FROM public.dialplan_extensions;")
        cur.execute("DELETE FROM public.dialplan_contexts;")
        conn.commit()
        logging.info("All dialplan data deleted successfully.")
    except Exception as e:
        conn.rollback()
        logging.error(f"Error deleting dialplan data: {e}")
        raise

def get_or_insert_context(conn, context_name, tenant_uuid):
    """
    Retrieves an existing dialplan context from the database by name.
    If the context does not exist, it creates a new one and returns its UUID.
    """
    try:
        cur = conn.cursor()
        cur.execute("SELECT context_uuid FROM public.dialplan_contexts WHERE context_name = ?", (context_name,))
        result = cur.fetchone()
        if result:
            logging.info(f"Context '{context_name}' already exists with UUID: {result[0]}")
            return result[0]
        
        context_uuid = str(uuid.uuid4())
        cur.execute("""
            INSERT INTO public.dialplan_contexts (context_uuid, tenant_uuid, context_name)
            VALUES (?, ?, ?);
        """, (context_uuid, tenant_uuid, context_name))
        conn.commit()
        logging.info(f"Context '{context_name}' inserted with UUID: {context_uuid}")
        return context_uuid
    except Exception as e:
        conn.rollback()
        logging.error(f"Error getting or inserting context '{context_name}': {e}")
        raise

def insert_extension(conn, context_uuid, extension_name, continue_val, priority=1):
    """
    Inserts an extension into the database under a specific context.
    """
    extension_uuid = str(uuid.uuid4())
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO public.dialplan_extensions (extension_uuid, context_uuid, extension_name, continue, priority)
            VALUES (?, ?, ?, ?, ?);
        """, (extension_uuid, context_uuid, extension_name, continue_val, priority))
        conn.commit()
        logging.info(f"Extension '{extension_name}' inserted with UUID: {extension_uuid}")
        return extension_uuid
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting extension '{extension_name}': {e}")
        raise

def insert_condition(conn, extension_uuid, field, expression, break_on_match, condition_order=1):
    """
    Inserts a condition into the database under a specific extension.
    """
    condition_uuid = str(uuid.uuid4())
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO public.dialplan_conditions 
            (condition_uuid, extension_uuid, field, expression, break_on_match, condition_order)
            VALUES (?, ?, ?, ?, ?, ?);
        """, (condition_uuid, extension_uuid, field, expression, break_on_match, condition_order))
        conn.commit()
        logging.info(f"Condition inserted for extension UUID '{extension_uuid}' with UUID: {condition_uuid}")
        return condition_uuid
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting condition: {e}")
        raise

def insert_action(conn, condition_uuid, action_type, application, data, action_order):
    """
    Inserts an action into the database under a specific condition.
    """
    action_uuid = str(uuid.uuid4())
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO public.dialplan_actions 
            (action_uuid, condition_uuid, action_type, application, data, action_order)
            VALUES (?, ?, ?, ?, ?, ?);
        """, (action_uuid, condition_uuid, action_type, application, data, action_order))
        conn.commit()
        logging.info(f"Action '{application}' inserted for condition UUID '{condition_uuid}'")
    except Exception as e:
        conn.rollback()
        logging.error(f"Error inserting action '{application}': {e}")
        raise

def migrate_dialplan(conn, tenant_uuid, directory):
    """
    Reads dialplan XML files from the specified directory and inserts them into the database.
    """
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

def main():
    conn = None
    try:
        conn = connect_db()
        tenant_uuid = get_default_tenant_uuid(conn)
        delete_dialplan_data(conn)
        migrate_dialplan(conn, tenant_uuid, DIALPLAN_DIR)
        logging.info("Migration completed successfully.")
    except Exception as e:
        logging.error(f"Error in migration process: {e}")
    finally:
        if conn:
            conn.close()
            logging.info("Database connection closed.")

if __name__ == "__main__":
    main()
