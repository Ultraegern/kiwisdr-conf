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
    pip3 install Flask
    echo "✅ Flask installed successfully: $(python3 -c 'import flask; print(flask.__version__)')"
fi

echo "⬜ Setting up api backend service..."
verify_signature $DIR/recorder/webui-backend/backend.py && sudo chmod +x $DIR/recorder/webui-backend/backend.py && sudo cp $DIR/recorder/webui-backend/backend.py /usr/local/bin/recorder-backend.py
sudo mkdir -p /var/recorder/recorded-files/gnss_pos/

echo "⬜ Setting up systemd service..."
verify_signature $DIR/recorder/webui-backend/backend.service && sudo cp $DIR/recorder/webui-backend/backend.service /etc/systemd/system/recorder-backend.service
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable recorder-backend.service
sudo systemctl start recorder-backend.service
sudo systemctl status recorder-backend.service --no-pager
echo "✅ recorder-backend.service is set up and running."