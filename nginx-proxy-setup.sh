#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if command_exists nginx; then
    echo "✅ Nginx is already installed: $(nginx -v)"
else
    echo "Installing Nginx..."
    sudo apt update -qq
    sudo apt install -y -qq nginx
    echo "✅ Nginx installed successfully: $(nginx -v)"
fi

# Install openssl if not installed
if command_exists openssl; then
    echo "✅ OpenSSL is already installed: $(openssl version)"
else
    echo "Installing OpenSSL..."
    sudo apt update -qq
    sudo apt install -y -qq openssl
    echo "✅ OpenSSL installed successfully: $(openssl version)"
fi

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

    #ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_protocols       TLSv1.2;
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




