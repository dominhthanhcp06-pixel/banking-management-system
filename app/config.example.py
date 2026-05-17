"""
Local database configuration — TEMPLATE.

USAGE
    1. Copy this file:  config.example.py  →  config.py
    2. Edit config.py and replace 'YOUR_MYSQL_PASSWORD_HERE' with your
       local MySQL root password.
    3. The real config.py is gitignored and will never be committed.

SECURITY NOTE
In a real production system, credentials would not live in a checked-in
Python file. They would be loaded from environment variables, an
operating-system credential store, or a secrets manager. For this
academic project we accept the simpler file-based approach and discuss
the trade-off in the report's Security section.
"""

DB_CONFIG = {
    'host':     'localhost',
    'port':     3306,
    'user':     'root',
    'password': 'YOUR_MYSQL_PASSWORD_HERE',   # <-- edit this in your local config.py
    'database': 'banking_system',
    'charset':  'utf8mb4',
    'use_unicode': True,
    'autocommit':  False,
}

# AES key used to read the encrypted national_id column.
# Must match the key used by data/load_data.py.
AES_KEY = 'BMS_AES_KEY_2026'
