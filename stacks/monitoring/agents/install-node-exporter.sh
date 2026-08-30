#!/usr/bin/env bash
# install-node-exporter.sh - run on a remote node (PVE host / VPS) as root.
# Installs node_exporter as a systemd service on :9100.
set -euo pipefail

VERSION="${1:-1.9.1}"
BIN=/usr/local/bin/node_exporter
UNIT=/etc/systemd/system/node-exporter.service

if systemctl is-active --quiet node-exporter; then
    echo "node-exporter already running:"; systemctl status node-exporter --no-pager -l | head -3; exit 0
fi

ARCH=$(uname -m); case "$ARCH" in x86_64) A=amd64 ;; aarch64|arm64) A=arm64 ;; *) echo "unsupported arch $ARCH"; exit 1 ;; esac
TMP=$(mktemp -d)
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-${A}.tar.gz" -o "$TMP/ne.tgz"
tar -xzf "$TMP/ne.tgz" -C "$TMP"
install -m 0755 "$TMP/node_exporter-${VERSION}.linux-${A}/node_exporter" "$BIN"
rm -rf "$TMP"

cat > "$UNIT" <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=$BIN --web.listen-address=0.0.0.0:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node-exporter

echo "done. node_exporter listening on :9100"
echo "NOTE (VPS): if prometheus can't reach it, open the firewall for your home IP:"
echo "  ufw allow proto tcp from <your-home-ip> to any port 9100 && ufw reload"
