#!/usr/bin/env python3
"""
Configure 3x-ui panel to use the self-signed cert from cert/.
Run after 'make gen-cert' and after first 'make panel' (so that x-ui.db exists).

Cert paths inside the container (as mounted in compose.yml):
  /root/cert/cert.pem
  /root/cert/key.pem
"""
import sqlite3
import sys
import os

DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'db', 'x-ui.db')
CERT_FILE = "/root/cert/cert.pem"
KEY_FILE  = "/root/cert/key.pem"

def set_setting(cur, key, value):
    cur.execute("SELECT value FROM settings WHERE key=?", (key,))
    if cur.fetchone():
        cur.execute("UPDATE settings SET value=? WHERE key=?", (value, key))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (key, value))

def main():
    db_path = os.path.abspath(DB_PATH)
    if not os.path.exists(db_path):
        print(f"ERROR: DB not found at {db_path}")
        print("Start the panel first: make panel")
        sys.exit(1)

    cert_host_path = os.path.join(os.path.dirname(__file__), '..', 'cert', 'cert.pem')
    if not os.path.exists(os.path.abspath(cert_host_path)):
        print("ERROR: cert/cert.pem not found.")
        print("Generate the cert first: make gen-cert")
        sys.exit(1)

    con = sqlite3.connect(db_path)
    cur = con.cursor()

    set_setting(cur, "webCertFile", CERT_FILE)
    set_setting(cur, "webKeyFile",  KEY_FILE)

    con.commit()
    con.close()

    print(f"Panel SSL configured:")
    print(f"  cert: {CERT_FILE}")
    print(f"  key:  {KEY_FILE}")
    print()
    print("Restart the panel to apply: make panel")
    print("Panel will be available at https://localhost:${PANEL_PORT:-2083}")

if __name__ == "__main__":
    main()
