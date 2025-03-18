# FreeSWITCH Dialplan Configuration

## Overview

This repository contains configuration files, scripts, and SQL queries for managing a FreeSWITCH telephony system, with a focus on dynamic dialplan management using a PostgreSQL database. The goal is to maintain a flexible and scalable telephony setup while preserving default functionality and adding custom features like IVR menus.

The current project includes efforts to configure a custom IVR (`ivr_demo`) for extension `5000`, troubleshoot dialplan conflicts, and ensure compatibility with FreeSWITCH's core features.

## Purpose

- Store and version-control FreeSWITCH configurations and related database scripts.
- Document troubleshooting steps and solutions for dialplan issues.
- Provide a reusable foundation for future telephony projects.

## Repository Structure

<pre>
├── migration/           # Main path for migration scripts.
│   ├── directory/       # Migration script for directory
│   └── dialplan/        # Migration script for dialplan
├── lua/                 # Main path for lua scripts
│   ├── directory/       # Lua script for directory
│   └── dialplan/        # Lua script for dialplan
├── sql/                 # SQL script for create database, tables and indixes
├── docs/                # Additional documentation and notes
├── install.sh           # Installation script
└── README.md            # This file
</pre>

## Prerequisites

- **FreeSWITCH**: Version 1.10.12 or compatible (installed and running).
- **PostgreSQL**: Database for dynamic dialplan storage (e.g., `ring2all` database).
- **fs_cli**: FreeSWITCH command-line interface for testing and debugging.
- **Lua**: For dynamic XML generation (ensure `mod_lua` is enabled).

## Getting Started

1. **Get install.sh**
```console
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/install.sh
chmod +x install.sh
./install.sh
```
2. **Execute installxml.sh**
```console
wget https://raw.githubusercontent.com/VitalPBX/freeswitch/refs/heads/main/installxml.sh
chmod +x installxml.sh
./installxml.sh
```
3.- **Fill in the information or you can leave the default values.**
```console
Confirmed Configuration:
FreeSWITCH Database Name.............> $fs_database
FreeSWITCH User Name.................> $fs_user
FreeSWITCH Password..................> $fs_password
Ring2All CDR Database Name...........> $r2a_cdr_database
Ring2All CDR User Name...............> $r2a_cdr_user
Ring2All CDR Password................> $r2a_cdr_password
Ring2All Database Name...............> $r2a_database
Ring2All User Name...................> $r2a_user
Ring2All Password....................> $r2a_password
FreeSWITCH Default Password for SIP..> $fs_default_password
FreeSWITCH Token.....................> $fs_token
```
## Current Features
- Custom IVR for extension 5000 (ivr_demo) with answer, sleep, and ivr actions.
- Dynamic dialplan generation using Lua and PostgreSQL.
- Troubleshooting logs and SQL fixes for common dialplan conflicts.

## Work in Progress
- Resolving conflicts with generic extensions (e.g., park) without removing functionality.
- Ensuring ivr_demo executes reliably with high priority.

## Contributing
Feel free to fork this repository, submit pull requests, or open issues for suggestions and bug reports. Contributions to improve stability, add features, or enhance documentation are welcome!

## License
This project is licensed under the MIT License (or choose another license if preferred).

## Acknowledgments
- Built with assistance from Grok 3 by xAI for troubleshooting and code suggestions.
- Inspired by FreeSWITCH community documentation and examples.
