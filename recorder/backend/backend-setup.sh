#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

source /tmp/kiwisdr-conf-main/setup.sh # Load verify_signature()
DIR=/tmp/kiwisdr-conf-main

ARCH=$(uname -m)
echo "⬜ Detected system architecture: $ARCH"

# Map architecture to Rust target directories
case "$ARCH" in
    x86_64)
        TARGET_DIR="x86_64-unknown-linux-gnu"
        ;;
    aarch64)
        TARGET_DIR="aarch64-unknown-linux-gnu"
        ;;
    armv7l|armv6l)
        TARGET_DIR="armv7-unknown-linux-gnueabihf"
        ;;
    *)
        echo "❌ Unsupported architecture: $ARCH"
        echo "   Supported: x86_64, aarch64, armv7l, armv6l"
        exit 1
        ;;
esac

BINARY_PATH="$DIR/recorder/backend/target/$TARGET_DIR/release/backend"

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "❌ Compiled binary not found for $ARCH."
    echo "   Expected at: $BINARY_PATH"
    echo "   Please compile it with: cargo build --release --target=$TARGET_DIR"
    exit 1
fi

echo "⬜ Setting up recorder backend..."
verify_signature "$BINARY_PATH"
sudo install -m 755 "$BINARY_PATH" /usr/local/bin/kiwirecorder-backend

sudo mkdir -p /var/recorder/recorded-files/gnss_pos/

echo "⬜ Setting up systemd service..."
verify_signature "$DIR/recorder/backend/backend.service"
sudo cp "$DIR/recorder/backend/backend.service" /etc/systemd/system/kiwirecorder-backend.service

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl stop kiwirecorder-backend.service
sudo systemctl enable kiwirecorder-backend.service
sudo systemctl restart kiwirecorder-backend.service

systemctl status kiwirecorder-backend.service


echo "✅ Api setup complete."
echo "ℹ️ To view logs: journalctl -u kiwirecorder-backend.service -f"
