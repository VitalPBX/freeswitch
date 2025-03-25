#!/usr/bin/env python3

import re
import uuid
import pyodbc
from datetime import datetime

# Configuration
ODBC_DSN = "ring2all"
VARS_XML = "/etc/freeswitch/vars.xml"  # Ruta a tu archivo vars.xml

# Connect to the database
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Utility: current UTC timestamp
def now():
    return datetime.utcnow()

# Parse vars.xml and insert variables into the database
def migrate_global_vars(xml_path):
    try:
        with open(xml_path, "r", encoding="utf-8") as file:
            lines = file.readlines()

        current_comment = "Uncategorized"
        inserted = 0

        for line in lines:
            # Detect comment blocks
            comment_match = re.match(r'\s*<!--\s*(.*?)\s*-->', line)
            if comment_match:
                current_comment = comment_match.group(1).strip().replace("'", "''")
                continue

            # Detect variable lines
            var_match = re.match(r'\s*<X-PRE-PROCESS cmd="set" data="(.*?)=(.*?)"\s*/?>', line)
            if var_match:
                name = var_match.group(1).strip()
                value = var_match.group(2).strip().replace("'", "''")
                description = current_comment

                var_id = str(uuid.uuid4())

                cursor.execute("""
                    INSERT INTO core.global_vars (
                        id, tenant_id, name, value, enabled, description,
                        insert_date, insert_user
                    ) VALUES (?, NULL, ?, ?, ?, ?, ?, ?)
                """, (
                    var_id,
                    name,
                    value,
                    True,
                    description,
                    now(),
                    None  # Optional: replace with user UUID if available
                ))

                inserted += 1
                print(f"✅ Variable '{name}' inserted (description: '{description}')")

        conn.commit()
        print(f"\n✅ Migration complete: {inserted} global variables inserted.")

    except Exception as e:
        print(f"❌ Error processing vars.xml: {e}")

# Run migration
migrate_global_vars(VARS_XML)

# Close connection
cursor.close()
conn.close()
print("✅ Database connection closed.")
