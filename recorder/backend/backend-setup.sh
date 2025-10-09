#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

source /tmp/kiwisdr-conf-main/setup.sh # Load verify_signature()
DIR=/tmp/kiwisdr-conf-main

echo "⬜ Setting up recorder backend..."

# Verify and install binary
verify_signature $DIR/recorder/backend/target/release/backend
sudo install -m 755 $DIR/recorder/backend/target/release/backend /usr/local/bin/kiwirecorder-backend

sudo mkdir -p /var/recorder/recorded-files/gnss_pos/

echo "⬜ Setting up systemd service..."
verify_signature $DIR/recorder/backend/backend.service
sudo cp $DIR/recorder/backend/backend.service /etc/systemd/system/kiwirecorder-backend.service

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable kiwirecorder-backend.service
sudo systemctl start kiwirecorder-backend.service
sudo systemctl status kiwirecorder-backend.service --no-pager

echo "✅ kiwirecorder-backend.service is set up and running."
echo "ℹ️ To view logs: journalctl -u kiwirecorder-backend.service -f"
