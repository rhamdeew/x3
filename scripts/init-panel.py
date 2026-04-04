#!/usr/bin/env python3
"""
First-run initialization for 3x-ui panel.
Runs inside the container via: docker exec overseer python3 /scripts/init-panel.py

Reads from environment:
  PANEL_PORT  — panel port (default: 2083)
  PANEL_USER  — login username (default: admin)
  PANEL_PASS  — login password (default: admin)
  PANEL_PATH  — URL base path (default: /get)
"""
import sqlite3
import json
import os
import subprocess
import sys

PORT = os.environ.get("PANEL_PORT", "2083")
USER = os.environ.get("PANEL_USER", "admin")
PASS = os.environ.get("PANEL_PASS", "admin")
PATH = os.environ.get("PANEL_PATH", "/get")
DB   = "/etc/x-ui/x-ui.db"

# Complete xray template — must include outbounds or 3x-ui panel JS breaks
XRAY_TEMPLATE = {
    "log": {"loglevel": "warning"},
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "domain": ["ru"], "outboundTag": "direct"},
            {"type": "field", "ip": ["geoip:ru"],  "outboundTag": "direct"},
        ]
    },
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {"domainStrategy": "AsIs", "redirect": "", "noises": []}
        },
        {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {"response": {"type": "http"}}
        }
    ],
    "stats": {}
}

def set_setting(cur, key, value):
    cur.execute("SELECT value FROM settings WHERE key=?", (key,))
    if cur.fetchone():
        cur.execute("UPDATE settings SET value=? WHERE key=?", (value, key))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?,?)", (key, value))

# ── 1. Port / username / password / basepath via x-ui CLI ─────────────────────
print("Applying panel settings via x-ui CLI...")
result = subprocess.run(
    ["/app/x-ui", "setting",
     "-port",        PORT,
     "-username",    USER,
     "-password",    PASS,
     "-webBasePath", PATH],
    capture_output=True, text=True
)
output = (result.stdout + result.stderr).strip()
if output:
    print(" ", output)
if result.returncode != 0:
    print("ERROR: x-ui setting failed", file=sys.stderr)
    sys.exit(1)

# ── 2. Cert + sub + xray template via DB ──────────────────────────────────────
print("Applying DB settings...")
con = sqlite3.connect(DB)
cur = con.cursor()

set_setting(cur, "webCertFile", "/root/cert/cert.pem")
set_setting(cur, "webKeyFile",  "/root/cert/key.pem")
print("  SSL cert configured")

set_setting(cur, "subEnable", "false")
print("  subscription service disabled")

set_setting(cur, "xrayTemplateConfig", json.dumps(XRAY_TEMPLATE))
print("  xray template set (routing: .ru → direct)")

con.commit()
con.close()

print(f"\nDone. Panel will be at https://<host>:{PORT}{PATH}")
