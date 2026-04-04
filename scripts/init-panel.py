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
import os
import subprocess
import sys

PORT = os.environ.get("PANEL_PORT", "2083")
USER = os.environ.get("PANEL_USER", "admin")
PASS = os.environ.get("PANEL_PASS", "admin")
PATH = os.environ.get("PANEL_PATH", "/get")
DB   = "/etc/x-ui/x-ui.db"

# ── Routing rules ──────────────────────────────────────────────────────────────
import json

RU_DOMAIN_RULE = {
    "type": "field",
    "domain": ["geosite:ru", "geosite:category-gov-ru"],
    "outboundTag": "direct"
}
RU_IP_RULE = {
    "type": "field",
    "ip": ["geoip:ru"],
    "outboundTag": "direct"
}

def set_setting(cur, key, value):
    cur.execute("SELECT value FROM settings WHERE key=?", (key,))
    if cur.fetchone():
        cur.execute("UPDATE settings SET value=? WHERE key=?", (value, key))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?,?)", (key, value))

def apply_routing(cur):
    cur.execute("SELECT value FROM settings WHERE key='xrayTemplateConfig'")
    row = cur.fetchone()
    config = {}
    if row and row[0]:
        try:
            config = json.loads(row[0])
        except json.JSONDecodeError:
            pass

    routing = config.get("routing", {"domainStrategy": "IPIfNonMatch", "rules": []})
    rules   = routing.get("rules", [])
    modified = False

    if not any("geoip:ru" in str(r.get("ip", [])) for r in rules):
        rules.insert(0, RU_IP_RULE)
        modified = True
        print("  routing: added geoip:ru → direct")

    if not any("geosite:ru" in str(r.get("domain", [])) for r in rules):
        rules.insert(0, RU_DOMAIN_RULE)
        modified = True
        print("  routing: added geosite:ru → direct")

    if modified:
        routing.setdefault("domainStrategy", "IPIfNonMatch")
        routing["rules"] = rules
        config["routing"] = routing
        set_setting(cur, "xrayTemplateConfig", json.dumps(config))
    else:
        print("  routing: already configured")

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

# ── 2. Cert + sub + routing via DB ────────────────────────────────────────────
print("Applying DB settings...")
con = sqlite3.connect(DB)
cur = con.cursor()

set_setting(cur, "webCertFile", "/root/cert/cert.pem")
set_setting(cur, "webKeyFile",  "/root/cert/key.pem")
print("  SSL cert configured")

set_setting(cur, "subEnable", "false")
print("  subscription service disabled")

apply_routing(cur)

con.commit()
con.close()

print(f"\nDone. Panel will be at https://<host>:{PORT}{PATH}")
