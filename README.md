# FreeSWITCH Dialplan Configuration

## Overview

This repository contains configuration files, scripts, and SQL queries for managing a FreeSWITCH telephony system, with a focus on dynamic dialplan management using a PostgreSQL database. The goal is to maintain a flexible and scalable telephony setup while preserving default functionality and adding custom features like IVR menus.

The current project includes efforts to configure a custom IVR (`ivr_demo`) for extension `5000`, troubleshoot dialplan conflicts, and ensure compatibility with FreeSWITCH's core features.

## Purpose

- Store and version-control FreeSWITCH configurations and related database scripts.
- Document troubleshooting steps and solutions for dialplan issues.
- Provide a reusable foundation for future telephony projects.

## Repository Structure

├── dialplan/           # Dialplan-related files and scripts
│   ├── sql/            # SQL queries for managing the dialplan in PostgreSQL
│   └── xml/            # Static XML dialplan snippets (if any)
├── ivr_menus/          # IVR menu configurations
├── logs/               # Sample FreeSWITCH logs for debugging
├── docs/               # Additional documentation and notes
└── README.md           # This file


## Prerequisites

- **FreeSWITCH**: Version 1.10.12 or compatible (installed and running).
- **PostgreSQL**: Database for dynamic dialplan storage (e.g., `ring2all` database).
- **fs_cli**: FreeSWITCH command-line interface for testing and debugging.
- **Lua**: For dynamic XML generation (ensure `mod_lua` is enabled).

## Getting Started

1. **Clone the Repository**
   ```bash
   git clone https://github.com/[your-username]/[your-repo-name].git
   cd [your-repo-name]
   
2. **Set Up FreeSWITCH**
- Ensure FreeSWITCH is installed and configured with PostgreSQL integration.
- Update conf/autoload_configs/lua.conf.xml to point to your Lua scripts if customized.

3.- **Database Configuration**
- Create the ring2all database in PostgreSQL (or adjust to your database name).
- Apply the SQL scripts in dialplan/sql/ to set up tables and initial dialplan data:

psql -U [your-username] -d ring2all -f dialplan/sql/setup.sql

4. **Deploy IVR Menus**
- Copy IVR configurations from ivr_menus/ to /usr/share/freeswitch/ivr_menus/ (adjust path based on your FreeSWITCH installation).
- Reload IVR menus:

fs_cli -x "reloadxml"

5. **Test the Configuration**
- Start FreeSWITCH and use fs_cli to monitor logs:

fs_cli
console loglevel debug

- Make a test call from extension 1000 to 5000 and check the output.

## Current Features
- Custom IVR for extension 5000 (ivr_demo) with answer, sleep, and ivr actions.
- Dynamic dialplan generation using Lua and PostgreSQL.
- Troubleshooting logs and SQL fixes for common dialplan conflicts.

## Work in Progress
- Resolving conflicts with generic extensions (e.g., park) without removing functionality.
- Ensuring ivr_demo executes reliably with high priority.
- Adding documentation for each dialplan extension’s purpose.

## Contributing
Feel free to fork this repository, submit pull requests, or open issues for suggestions and bug reports. Contributions to improve stability, add features, or enhance documentation are welcome!

## License
This project is licensed under the MIT License (or choose another license if preferred).

## Acknowledgments
- Built with assistance from Grok 3 by xAI for troubleshooting and code suggestions.
- Inspired by FreeSWITCH community documentation and examples.
