#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Install prerequisites
sudo apt update -qq
sudo apt install -y -qq curl gnupg2 ca-certificates lsb-release debian-archive-keyring
	
# Configure repository keys
curl -sSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# Verify repository key fingerprints
EXPECTED_FINGERPRINT="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"
FINGERPRINT_OUTPUT=$(gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg)
if grep -q "$EXPECTED_FINGERPRINT" <<< "$FINGERPRINT_OUTPUT"; then
    echo "✅ Fingerprint verified: $EXPECTED_FINGERPRINT"
else
    echo "❌ Fingerprint verification failed!"
    echo "Output was:"
    echo "$FINGERPRINT_OUTPUT"
    exit 1
fi

# Configure repository
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian `lsb_release -cs` nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null

# Install nginx
sudo apt update -qq
sudo apt install nginx -y -qq
sudo systemctl enable nginx --quiet
sudo systemctl start nginx --quiet
sleep 2
sudo systemctl status nginx --no-pager

# Verify installation
nginx -v




