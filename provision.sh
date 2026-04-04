#!/usr/bin/env bash
# provision.sh — Ubuntu 24 server setup
# Run as root: bash provision.sh
set -euo pipefail

# ── Guards ────────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root" >&2
    exit 1
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    echo "ERROR: Ubuntu only" >&2
    exit 1
fi

# ── 1. Docker + vim ───────────────────────────────────────────────────────────
echo "==> Installing Docker and vim..."

apt-get update -qq
apt-get install -y -qq ca-certificates curl vim

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
echo "    Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"

# ── 2. User www ───────────────────────────────────────────────────────────────
echo "==> Creating user www..."

if id www &>/dev/null; then
    echo "    User www already exists, skipping creation."
else
    useradd --create-home --home-dir /srv/www --shell /bin/bash www
    echo "    Created user www with home /srv/www"
fi

# Copy root authorized_keys
ROOT_KEYS="${HOME}/.ssh/authorized_keys"
WWW_SSH="/srv/www/.ssh"

if [[ -f "$ROOT_KEYS" ]]; then
    mkdir -p "$WWW_SSH"
    cp "$ROOT_KEYS" "$WWW_SSH/authorized_keys"
    chown -R www:www "$WWW_SSH"
    chmod 700 "$WWW_SSH"
    chmod 600 "$WWW_SSH/authorized_keys"
    echo "    Copied $(wc -l < "$ROOT_KEYS") key(s) from root's authorized_keys"
else
    echo "    WARNING: $ROOT_KEYS not found — www has no authorized_keys"
fi

# ── 3. SSH port ───────────────────────────────────────────────────────────────
echo "==> Reconfiguring SSH port..."

NEW_PORT=$(shuf -i 1800-2000 -n 1)
SSHD_CONFIG="/etc/ssh/sshd_config"

# Remove any existing Port lines (commented or not) and append the new one
sed -i -E '/^#?Port\s+/d' "$SSHD_CONFIG"
echo "Port $NEW_PORT" >> "$SSHD_CONFIG"

# Validate config before restarting
sshd -t
systemctl restart ssh

echo "    SSH port set to: $NEW_PORT"

# Warn about firewall if ufw is active
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    echo ""
    echo "    WARNING: ufw is active. Run before disconnecting:"
    echo "      ufw allow $NEW_PORT/tcp"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Done."
echo "  SSH port : $NEW_PORT"
echo "  User     : www  (home: /srv/www)"
echo ""
echo "  IMPORTANT: open a new SSH session on port $NEW_PORT before closing this one."
