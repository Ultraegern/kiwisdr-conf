#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

source /tmp/kiwisdr-conf-main/setup.sh # Load verify_signature()
DIR=/tmp/kiwisdr-conf-main

# Install Python and Flask if not installed
if command -v python3 &>/dev/null && python3 -c "import flask" &>/dev/null; then
    echo "✅ Python3 and Flask are already installed: $(python3 --version), Flask $(python3 -c 'import flask; print(flask.__version__)')"
else
    echo "⬜ Installing Python3... (this may take a while)"
    sudo apt update -qq
    sudo apt install -y -qq python3 python3-pip
    echo "✅ Python3 installed successfully: $(python3 --version)"
    echo "⬜ Installing Flask..."
    pip3 install --only-binary=:all: Flask markupsafe
    echo "✅ Flask installed successfully: $(python3 -c 'import flask; print(flask.__version__)')"
fi

echo "⬜ Setting up api backend service..."
verify_signature $DIR/recorder/webui-backend/backend.py && sudo chmod +x $DIR/recorder/webui-backend/backend.py && sudo cp $DIR/recorder/webui-backend/backend.py /usr/local/bin/recorder-backend.py
sudo mkdir -p /var/recorder/recorded-files/gnss_pos/

echo "⬜ Configuring /etc/fstab for SD card auto-mount..."
DEVICE="/dev/mmcblk0p1"
FSTAB="/etc/fstab"
MOUNT_POINT="/mnt/sdcard"
sudo mkdir -p $MOUNT_POINT
# Verify block device exists
if [ ! -b "$DEVICE" ]; then
  echo "⚠️ SD card not found. Please insert an SD card to enable recording functionality."
  exit 0
else
    # Get UUID and filesystem type
    UUID=$(blkid -s UUID -o value "$DEVICE")
    if [ -z "$UUID" ]; then
    echo "❌ Unable to read UUID from $DEVICE." >&2
    exit 1
    fi
    FSTYPE=$(blkid -s TYPE -o value "$DEVICE")
    if [ -z "$FSTYPE" ]; then
    echo "❌ Unable to detect filesystem type on $DEVICE." >&2
    exit 1
    fi
    # Check if fstab already contains this UUID
    if grep -q "UUID=$UUID" "$FSTAB"; then
    echo "ℹ️ An entry for UUID=$UUID already exists in $FSTAB."
    exit 0
    fi
    # Append to /etc/fstab  
    echo "UUID=$UUID $MOUNT_POINT $FSTYPE defaults,noatime 0 0" | sudo tee -a "$FSTAB" > /dev/null
    sudo tail -n 1 "$FSTAB"
    mkdir -p $MOUNT_POINT/recorded-files/gnss_pos/
    echo "✅ /etc/fstab configured to auto-mount SD card at /mnt/sdcard."
    sudo mount -a
    echo "✅ SD card mounted at /mnt/sdcard."
fi


echo "⬜ Setting up systemd service..."
verify_signature $DIR/recorder/webui-backend/backend.service && sudo cp $DIR/recorder/webui-backend/backend.service /etc/systemd/system/recorder-backend.service
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable recorder-backend.service
sudo systemctl start recorder-backend.service
sudo systemctl status recorder-backend.service --no-pager
echo "✅ recorder-backend.service is set up and running."