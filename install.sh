#!/bin/bash
set -e

# Author:      Rodrigo Cuadra
# Date:        Feb-2024
# Support:     rcuadra@vitalpbx.com
# Description: This script automates the installation of FreeSWITCH with PostgreSQL integration from deb.

# Color codes for terminal output
green="\033[00;32m"
red="\033[0;31m"
txtrst="\033[00;0m"

# Welcome message
echo -e "****************************************************"
echo -e "*     Welcome to the FreeSWITCH Installation       *"
echo -e "*         All options are mandatory                *"
echo -e "****************************************************"

# Set default values for FreeSWITCH configuration
fs_database="freeswitch"
fs_user="freeswitch"
fs_password="fs2025"
r2a_cdr_database="ring2all_cdr"
r2a_cdr_user="ring2all"
r2a_cdr_password="r2a2025"
r2a_database="ring2all"
r2a_user="ring2all"
r2a_password="r2a2025"
fs_default_password="fs2026"
fs_token="pat_T4vJsv4Ks6i3W8ynCoxnWkpD"

# Load configuration from file if it exists
filename="config.txt"
if [ -f "$filename" ]; then
    echo -e "Config file found. Loading settings..."
    n=1
    while read -r line; do
        case $n in
            1) fs_database=${line:-$fs_database} ;;
            2) fs_user=${line:-$fs_user} ;;
            3) fs_password=${line:-$fs_password} ;;
            4) r2a_cdr_database=${line:-$r2a_cdr_database} ;;
            5) r2a_cdr_user=${line:-$r2a_cdr_user} ;;
            6) r2a_cdr_password=${line:-$r2a_cdr_password} ;;
            7) r2a_database=${line:-$r2a_database} ;;
            8) r2a_user=${line:-$r2a_user} ;;
            9) r2a_password=${line:-$r2a_password} ;;
            10) fs_default_password=${line:-$fs_default_password} ;;
            11) fs_token=${line:-$fs_token} ;;
        esac
        n=$((n+1))
    done < "$filename"
fi

# Prompt user to confirm or change default values
echo -e "Please confirm or change the following configuration settings:"
read -p "FreeSWITCH Database Name [$fs_database]: " input && fs_database="${input:-$fs_database}"
read -p "FreeSWITCH User Name [$fs_user]: " input && fs_user="${input:-$fs_user}"
read -p "FreeSWITCH Password [$fs_password]: " input && fs_password="${input:-$fs_password}"
read -p "Ring2All CDR Database Name [$r2a_cdr_database]: " input && r2a_cdr_database="${input:-$r2a_cdr_database}"
read -p "Ring2All CDR User Name [$r2a_cdr_user]: " input && r2a_cdr_user="${input:-$r2a_cdr_user}"
read -p "Ring2All CDR Password [$r2a_cdr_password]: " input && r2a_cdr_password="${input:-$r2a_cdr_password}"
read -p "Ring2All Database Name [$r2a_database]: " input && r2a_database="${input:-$r2a_database}"
read -p "Ring2All User Name [$r2a_user]: " input && r2a_user="${input:-$r2a_user}"
read -p "Ring2All Password [$r2a_password]: " input && r2a_password="${input:-$r2a_password}"
read -p "FreeSWITCH Default Password for SIP [$fs_default_password]: " input && fs_default_password="${input:-$fs_default_password}"
read -p "FreeSWITCH Token [$fs_token]: " input && fs_token="${input:-$fs_token}"

# Display confirmed configuration
echo -e "Confirmed Configuration:"
echo -e "FreeSWITCH Database Name.............> $fs_database"
echo -e "FreeSWITCH User Name.................> $fs_user"
echo -e "FreeSWITCH Password..................> $fs_password"
echo -e "Ring2All CDR Database Name...........> $r2a_cdr_database"
echo -e "Ring2All CDR User Name...............> $r2a_cdr_user"
echo -e "Ring2All CDR Password................> $r2a_cdr_password"
echo -e "Ring2All Database Name...............> $r2a_database"
echo -e "Ring2All User Name...................> $r2a_user"
echo -e "Ring2All Password....................> $r2a_password"
echo -e "FreeSWITCH Default Password for SIP..> $fs_default_password"
echo -e "FreeSWITCH Token.....................> $fs_token"

# Confirm configuration before proceeding
echo -e "***************************************************"
echo -e "*          Check Information                      *"
echo -e "***************************************************"
while [[ "$veryfy_info" != "yes" && "$veryfy_info" != "no" ]]; do
    read -p "Are you sure to continue with these settings? yes,no > " veryfy_info
done

if [ "$veryfy_info" = "yes" ]; then
    echo -e "*****************************************"
    echo -e "*   Starting to run the scripts         *"
    echo -e "*****************************************"
else
    echo -e "*   Exiting the script. Please restart.  *"
    exit 1
fi

# Save configuration to file
echo -e "$fs_database" > config.txt
echo -e "$fs_user" >> config.txt
echo -e "$fs_password" >> config.txt
echo -e "$fs_cdr_database" >> config.txt
echo -e "$fs_cdr_user" >> config.txt
echo -e "$fs_cdr_password" >> config.txt
echo -e "$r2a_database" > config.txt
echo -e "$r2a_user" >> config.txt
echo -e "$r2a_password" >> config.txt
echo -e "$fs_default_password" >> config.txt
echo -e "$fs_token" >> config.txt

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

# Setup PostgreSQL
echo -e "************************************************************"
echo -e "*          Create the freeswitch database and user.        *"
echo -e "************************************************************"
# Create databases and user
cd /tmp
sudo -u postgres psql -c "CREATE ROLE $fs_user WITH LOGIN PASSWORD '$fs_password'";
sudo -u postgres psql -c "CREATE DATABASE $fs_database OWNER $fs_user";
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $fs_database TO $fs_user";

# Create ring2all database
echo -e "************************************************************"
echo -e "*                  Create ring2all database                *"
echo -e "************************************************************"
wget -O ring2all.sql https://raw.githubusercontent.com/VitalPBX/freeswitch/main/sql/ring2all.sql
sed -i "s/\$r2a_database/$r2a_database/g; \
        s/\$r2a_user/$r2a_user/g; \
        s/\$r2a_password/$r2a_password/g" ring2all.sql
sudo -u postgres psql -f ring2all.sql

# Create ring2all_cdr database
echo -e "************************************************************"
echo -e "*                Create ring2all_cdr database              *"
echo -e "************************************************************"
wget -O ring2all_cdr.sql https://raw.githubusercontent.com/VitalPBX/freeswitch/main/sql/ring2all_cdr.sql
sed -i "s/\\\$r2a_cdr_database/$r2a_cdr_database/g; \
        s/\\\$r2a_cdr_user/$r2a_cdr_user/g" ring2all_cdr.sql
sudo -u postgres psql -f ring2all_cdr.sql

# Download and Install FreeSWITCH
echo -e "************************************************************"
echo -e "*          Installing FreeSWITCH version 1.10.12           *"
echo -e "************************************************************"
# Define your SignalWire authentication token (replace YOUR_TOKEN)
TOKEN=$fs_token

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

# Enable and start FreeSWITCH service
echo -e "************************************************************"
echo -e "*           Enabling and starting FreeSWITCH              *"
echo -e "************************************************************"
systemctl enable freeswitch
systemctl start freeswitch

# Allowing it to log Call Detail Records (CDRs) directly into a PostgreSQL database
echo -e "************************************************************"
echo -e "* FreeSWITCH, allowing it to log Call Detail Records (CDRs)*"
echo -e "*           directly into a PostgreSQL database.           *"
echo -e "************************************************************"
modules_conf="/etc/freeswitch/autoload_configs/modules.conf.xml"
sed -i '/<load module="mod_cdr_csv"\/>/a \    <load module="mod_cdr_pg_csv"/>' "$modules_conf"

# FreeSWITCH, allowing it to manage SIP user directories
echo -e "************************************************************"
echo -e "*  FreeSWITCH, allowing it to manage SIP user directories. *"
echo -e "************************************************************"
modules_conf="/etc/freeswitch/autoload_configs/modules.conf.xml"
sed -i 's/^\([[:space:]]*\)<!--\(<load module="mod_directory"\/>\)-->/\1\2/' "$modules_conf"

# Adding database connection data for CDRs
echo -e "************************************************************"
echo -e "*          Adding database connection data for CDRs        *"
echo -e "************************************************************"
# Path to configuration file
cdr_pg_csv_conf="/etc/freeswitch/autoload_configs/cdr_pg_csv.conf.xml"
# Check if file exists before modifying it
if [ -f "$cdr_pg_csv_conf" ]; then
  # Adding the Connection lines to the database
  sed -i '/<settings>/a\ \ \ \ <param name="core-db-dsn" value="freeswitch_cdr" />\n\ \ \ \ <param name="db-table" value="cdr"/>' "$cdr_pg_csv_conf"
  # Comment out the original connection line
  sed -i 's#^\(\s*\)<param name="db-info" value="host=localhost dbname=cdr connect_timeout=10" />#\1<!-- <param name="db-info" value="host=localhost dbname=cdr connect_timeout=10" /> -->#' "$cdr_pg_csv_conf"
  echo "✅ $cdr_pg_csv_conf file updated successfully."
else
  echo "❌ The file $cdr_pg_csv_conf does not exist."
fi

echo -e "************************************************************"
echo -e "*  Inserting core-db-dsn on line 181 of switch.conf.xml    *"
echo -e "************************************************************"
# Path to configuration file
switch_conf="/etc/freeswitch/autoload_configs/switch.conf.xml"
# Check if file exists before modifying it
if [ -f "$switch_conf" ]; then
  # Adding the Connection lines to the database on line 181
  sed -i "181i\    <param name=\"core-db-dsn\" value=\"odbc://freeswitch\" />" "$switch_conf"
  echo "✅ Line successfully inserted on line 181 of $switch_conf."
else
  echo "❌ The $switch_conf file does not exist."
fi

# FreeSWITCH, allowing it to freeswitch manage from Database
echo -e "************************************************************"
echo -e "*      Allowing it to freeswitch manage from Database      *"
echo -e "************************************************************"
lua_conf="/etc/freeswitch/autoload_configs/lua.conf.xml"
sed -i '/<settings>/a \    <param name="xml-handler-script" value="main.lua xml_handler"/>\n    <param name="xml-handler-bindings" value="directory,dialplan"/>' "$lua_conf"

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
[freeswitch]
Description         = PostgreSQL
Driver              = PostgreSQL Unicode
Trace               = No
TraceFile           = /tmp/psqlodbc.log
Database            = $fs_database
Servername          = 127.0.0.1
UserName            = $fs_user
Password            = $fs_password
Port                = 5432
ReadOnly            = No
RowVersioning       = No
ShowSystemTables    = No
ShowOidColumn       = No
FakeOidIndex        = No

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

[ring2all_cdr]
Description         = PostgreSQL
Driver              = PostgreSQL Unicode
Trace               = No
TraceFile           = /tmp/psqlodbc.log
Database            = cdr
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
wget -O directory_migrate_to_db.py https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/migration/directory/migrate_to_db.py
wget -O dialplan_migrate_to_db.py https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/migration/directory/migrate_to_db.py
wget -O main.lua https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/lua/main.lua
wget -O sip_register.lua https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/lua/directory/sip_register.lua
wget -O dialplna.lua https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/lua/dialplan/dialplna.lua

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

# Restart Freeswitch Service
echo -e "************************************************************"
echo -e "*                 Restart Freeswitch Service               *"
echo -e "************************************************************"
systemctl restart freeswitch

echo -e "************************************************************"
echo -e "*                 Installation Completed!                  *"
echo -e "************************************************************"
