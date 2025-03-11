#!/bin/bash

# Installation script for development and migration of XML files to a database.
# Also prepares and applies the database schema.
# Sets up the Lua structure for extension registration management.
# Handles dial plan management.

echo -e "************************************************************"
echo -e "*              Installing essential packages               *"
echo -e "************************************************************"

# Install basic dependencies
apt update && apt upgrade -y
apt install -y sudo gnupg2 wget lsb-release curl

# Install PostgreSQL
echo -e "************************************************************"
echo -e "*                    Installing PostgreSQL                 *"
echo -e "************************************************************"
sudo apt install -y postgresql postgresql-contrib lua-sql-postgres

# Enable and start PostgreSQL service
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Download and Install FreeSWITCH
echo -e "************************************************************"
echo -e "*          Installing FreeSWITCH version 1.10.12           *"
echo -e "************************************************************"

# Define your SignalWire authentication token (replace YOUR_TOKEN)
TOKEN="pat_T4vJsv4Ks6i3W8ynCoxnWkpD"

# Download SignalWire GPG key
wget --http-user=signalwire --http-password=$TOKEN -O /usr/share/keyrings/signalwire-freeswitch-repo.gpg \
    https://freeswitch.signalwire.com/repo/deb/debian-release/signalwire-freeswitch-repo.gpg

# Configure authentication credentials
echo "machine freeswitch.signalwire.com login signalwire password $TOKEN" > /etc/apt/auth.conf
chmod 600 /etc/apt/auth.conf

# Add SignalWire FreeSWITCH repository for Debian 12
echo "deb [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] \
https://freeswitch.signalwire.com/repo/deb/debian-release/ bookworm main" \
    | tee /etc/apt/sources.list.d/freeswitch.list
echo "deb-src [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] \
https://freeswitch.signalwire.com/repo/deb/debian-release/ bookworm main" \
    >> /etc/apt/sources.list.d/freeswitch.list

# Update package lists
apt update

# Install FreeSWITCH and required modules
apt install -y freeswitch freeswitch-meta-all \
               freeswitch-mod-pgsql freeswitch-mod-cdr-pg-csv

# FreeSWITCH, allowing it to manage SIP user directories and cdr database
echo -e "************************************************************"
echo -e "*  FreeSWITCH, allowing it to manage SIP user directories. *"
echo -e "************************************************************"
sed -i 's/^\([[:space:]]*\)<!--\(<load module="mod_directory"\/>\)-->/\1\2/' "/etc/freeswitch/autoload_configs/modules.conf.xml"
sed -i '/<load module="mod_cdr_csv"\/>/a \    <load module="mod_cdr_pg_csv"/>' "/etc/freeswitch/autoload_configs/modules.conf.xml"

# Enable and start FreeSWITCH service
echo -e "************************************************************"
echo -e "*           Enabling and starting FreeSWITCH              *"
echo -e "************************************************************"
systemctl enable freeswitch
systemctl start freeswitch

# Install Python environment and dependencies
echo -e "************************************************************"
echo -e "*         Setting up Python virtual environment           *"
echo -e "************************************************************"
apt install -y python3-psycopg2 python3-venv

# Create Python virtual environments
python3 -m venv /etc/ring2all/venv
python3 -m venv ~/myenv

# Activate and deactivate virtual environment (verification step)
source ~/myenv/bin/activate
deactivate

# Configure ODBC for PostgreSQL
echo -e "************************************************************"
echo -e "*    Configuring ODBC for PostgreSQL (odbc.ini setup)     *"
echo -e "************************************************************"

cat << EOF > /etc/odbc.ini
[ring2all]
Description         = PostgreSQL
Driver              = PostgreSQL Unicode
Trace               = No
TraceFile           = /tmp/psqlodbc.log
Database            = ring2all
Servername          = 127.0.0.1
UserName            = ring2all
Password            = ring2all
Port                = 5432
ReadOnly            = No
RowVersioning       = No
ShowSystemTables    = No
ShowOidColumn       = No
FakeOidIndex        = No
EOF

# Download database script, migration scrpts and lus acripts.
echo -e "************************************************************"
echo -e "*Download database script, migration scrpts and lus acripts*"
echo -e "************************************************************"
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/sql/ring2all.sql?token=GHSAT0AAAAAADAKQXBY7FUP5FZN6NNTQTTMZ6QJP3Q
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/migration/directory/directory_migrate_to_db.py?token=GHSAT0AAAAAADAKQXBZP3DHQOTDSCRLMRX6Z6QJPKQ
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/migration/dialplan/dialplan_migrate_to_db.py?token=GHSAT0AAAAAADAKQXBZTKCEKWXP7PZ5ZS4YZ6QJOVQ
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/lua/dialplan/main.lua?token=GHSAT0AAAAAADAKQXBYS7TQZJNZBO2B3XI2Z6QJQIQ
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/lua/directory/sip_register.lua?token=GHSAT0AAAAAADAKQXBY5W4TLDK2WCXSE6WMZ6QJQQQ
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/lua/dialplan/dialplna.lua?token=GHSAT0AAAAAADAKQXBYS7TQZJNZBO2B3XI2Z6QJQIQ

# Create database.
echo -e "************************************************************"
echo -e "*          Create database, tables and indexes             *"
echo -e "************************************************************"
sudo -u postgres psql -d ring2all -f dialplan/sql/setup.sql

# Migrate from XML to Database Directory.
echo -e "************************************************************"
echo -e "*       Migrate from XML to Database Directory.            *"
echo -e "************************************************************"
chmod +x directory_migrate_to_db.py
python3 directory_migrate_to_db.py

# Migrate from XML to Database Dialplan.
echo -e "************************************************************"
echo -e "*       Migrate from XML to Database Dialplan.             *"
echo -e "************************************************************"
chmod +x dialplan_migrate_to_db.py
python3 dialplan_migrate_to_db.py

# Create main.lua file
echo -e "************************************************************"
echo -e "*                   Create main.lua file                   *"
echo -e "************************************************************"
mv main.lua /usr/share/freeswitch/scripts/main.lua

# Create Lua Script for management user registration (directory)
echo -e "************************************************************"
echo -e "*     Create Lua Script for management user registration   *"
echo -e "************************************************************"
mkdir -p /usr/share/freeswitch/scripts/xml_handlers/directory
mv sip_register.lua /usr/share/freeswitch/scripts/xml_handlers/directory/sip_register.lua

# Create Lua Script for management dialplan (dialplan)
echo -e "************************************************************"
echo -e "*         Create Lua Script for management dialplan        *"
echo -e "************************************************************"
mkdir -p /usr/share/freeswitch/scripts/xml_handlers/dialplan
mv sip_register.lua /usr/share/freeswitch/scripts/xml_handlers/dialplan/dialplan.lua

# FreeSWITCH, allowing it to freeswitch manage from Database
echo -e "************************************************************"
echo -e "*      Allowing it to freeswitch manage from Database      *"
echo -e "************************************************************"
sed -i '/<settings>/a \    <param name="xml-handler-script" value="main.lua xml_handler"/>\n    <param name="xml-handler-bindings" value="directory,dialplan"/>' "/etc/freeswitch/autoload_configs/lua.conf.xml"

# Restart Freeswitch Service
echo -e "************************************************************"
echo -e "*                 Restart Freeswitch Service               *"
echo -e "************************************************************"
systemctl restart freeswitch

echo -e "************************************************************"
echo -e "*                 Installation Completed!                  *"
echo -e "************************************************************"
