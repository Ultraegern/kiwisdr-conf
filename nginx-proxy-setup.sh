#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Install prerequisites
#sudo apt update -qq
#sudo apt install -y -qq curl gnupg2 ca-certificates lsb-release debian-archive-keyring
	
# Configure repository keys
#curl -sSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

## Verify repository key fingerprints
#EXPECTED_FINGERPRINT="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"
#FINGERPRINT_OUTPUT=$(gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg)
#if grep -q "$EXPECTED_FINGERPRINT" <<< "$FINGERPRINT_OUTPUT"; then
#    echo "✅ Fingerprint verified: $EXPECTED_FINGERPRINT"
#else
#    echo "❌ Fingerprint verification failed!"
#    echo "Output was:"
#    echo "$FINGERPRINT_OUTPUT"
#    exit 1
#fi

## Configure repository
#echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian `lsb_release -cs` nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
#echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null

# Install nginx
echo "Updating package lists"
sudo apt update -qq
echo "Installing Nginx and OpenSSL"
sudo apt install nginx openssl -y -qq

# Verify installation
nginx -v
echo "✅ Nginx and OpenSSl installed successfully"

# Create a self-signed SSL certificate
echo "Creating self-signed SSL certificate"
SSL_DIR="/etc/ssl/kiwisdr"
sudo mkdir -p "$SSL_DIR"
sudo openssl req -x509 -nodes -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=Org/CN=kiwisdr.local" \
  -newkey rsa:2048 \
  -keyout "$SSL_DIR/kiwisdr.key" \
  -out "$SSL_DIR/kiwisdr.crt"

# Configure Nginx reverse proxy for kiwisdr.local
echo "Configuring Nginx Proxy for kiwisdr.local"
NGINX_CONF="/etc/nginx/sites-available/kiwisdr"
sudo tee "$NGINX_CONF" > /dev/null <<'EOF'
server {
    listen 80;
    server_name kiwisdr.local;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name kiwisdr.local;

    ssl_certificate     $SSL_DIR/kiwisdr.crt;
    ssl_certificate_key $SSL_DIR/kiwisdr.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:8073;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Enable the site
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/kiwisdr

# Test configuration and reload Nginx
sudo nginx -t
sudo systemctl reload nginx

echo "✅ Nginx is configured. Access KiwiSDR at https://kiwisdr.local"




