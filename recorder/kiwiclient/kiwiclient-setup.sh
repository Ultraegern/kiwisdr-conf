#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}


# Install kiwirecorder if not installed
if command_exists kiwirecorder; then
    echo "✅ kiwirecorder is already installed"
else
    echo "⬜ Refreshing package lists..."
    sudo apt update -qq
    echo "⬜ Installing dependencies..."
    sudo apt install -qq -y python3 python3-pip git make libsamplerate0
    sudo apt install -qq -y python3-numpy python3-cffi

    echo "⬜ Cloning kiwiclient repository..."
    sudo mkdir -p /usr/local/src
    cd /usr/local/src
    git clone https://github.com/jks-prv/kiwiclient.git kiwiclient
    cd kiwiclient

    echo "⬜ Building libsamplerate wrapper..."
    make samplerate_build

    echo "⬜ Creating symlink for convenience..."
    sudo ln -sf /usr/local/src/kiwiclient/kiwirecorder.py /usr/local/bin/kiwirecorder
    sudo chmod +x /usr/local/bin/kiwirecorder

    echo "✅ kiwirecorder installed successfully"
fi