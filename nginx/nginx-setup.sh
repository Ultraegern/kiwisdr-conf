#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

source ../setup.sh # Load verify_signature()

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install nginx if not installed
if command_exists nginx; then
    echo "✅ Nginx is already installed: $(nginx -v 2>&1)"
else
    echo "⬜ Installing Nginx..."
    sudo apt update -qq
    sudo apt install -y -qq nginx
    echo "✅ Nginx installed successfully: $(nginx -v 2>&1)"
fi

# Install openssl if not installed
if command_exists openssl; then
    echo "✅ OpenSSL is already installed: $(openssl version)"
else
    echo "⬜ Installing OpenSSL..."
    sudo apt update -qq
    sudo apt install -y -qq openssl
    echo "✅ OpenSSL installed successfully: $(openssl version)"
fi

# Generate self-signed TLS certificate
echo "⬜ Generating self-signed TLS certificate"
verify_signature ./cert/renew-cert.sh && sudo ./cert/renew-cert.sh
echo "✅ Self-signed TLS certificate created at $SSL_DIR"


echo "⬜ Setting up monthly certificate renewal with systemd..."

# Renewal script
verify_signature ./cert/renew-cert.sh && sudo cp ./cert/renew-cert.sh /usr/local/bin/renew-proxy-cert.sh

# Systemd service with logging
verify_signature ./cert/renew-cert.service && sudo cp ./cert/renew-cert.service /etc/systemd/system/proxy-cert-renew.service

# Systemd timer
verify_signature ./cert/renew-cert.timer && sudo cp ./cert/renew-cert.timer /etc/systemd/system/proxy-cert-renew.timer

# Enable and start the timer
sudo systemctl daemon-reload
sudo systemctl enable proxy-cert-renew.timer
sudo systemctl start proxy-cert-renew.timer

echo "✅ Monthly certificate renewal via systemd is set up."
echo "ℹ️ To view certificate renewal logs: journalctl -u proxy-cert-renew.service"


# Custom 502 error page
verify_signature html/502.html && sudo cp html/502.html /var/www/html/502.html

# Recorder front end
verify_signature html/recorder.html && sudo cp html/recorder.html /var/www/html/recorder.html

# Configure Nginx
echo "⬜ Configuring Nginx"
verify_signature nginx/nginx.conf && sudo cp nginx/nginx.conf /etc/nginx/sites-available/kiwisdr

# Enable the site
sudo ln -sf /etc/nginx/sites-available/kiwisdr /etc/nginx/sites-enabled/kiwisdr

# Test configuration and reload Nginx
sudo nginx -t > /dev/null 2>&1
sudo systemctl reload nginx

echo "✅ Nginx is configured. Access KiwiSDR at https://kiwisdr.local"