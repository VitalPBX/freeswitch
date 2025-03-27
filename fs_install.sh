#!/bin/bash
set -e

# Author:      Rodrigo Cuadra
# Date:        March-2025
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

echo -e "************************************************************"
echo -e "*              Installing essential packages               *"
echo -e "************************************************************"
# Install basic dependencies
apt update && apt upgrade -y
apt install -y sudo gnupg2 wget lsb-release curl sngrep net-tools

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
               freeswitch-mod-pgsql freeswitch-mod-cdr-pg-csv freeswitch-mod-odbc-cdr

# Enable and start FreeSWITCH service
echo -e "************************************************************"
echo -e "*           Enabling and starting FreeSWITCH              *"
echo -e "************************************************************"
systemctl enable freeswitch
systemctl start freeswitch

# Restart Freeswitch Service
echo -e "************************************************************"
echo -e "*                 Restart Freeswitch Service               *"
echo -e "************************************************************"
systemctl restart freeswitch

echo -e "************************************************************"
echo -e "*                 Installation Completed!                  *"
echo -e "************************************************************"
