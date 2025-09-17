#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

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
SSL_DIR="/etc/ssl/kiwisdr"
sudo mkdir -p "$SSL_DIR"
sudo openssl req -x509 -nodes -days 90 \
  -subj "/C=DK/ST=Aarhus/L=Skyby/O=SkyTEM Surveys/OU=SkyTEM Surveys/CN=kiwisdr.local" \
  -newkey rsa:2048 \
  -keyout "$SSL_DIR/kiwisdr.key" \
  -out "$SSL_DIR/kiwisdr.crt" \
  >/dev/null 2>&1
echo "✅ Self-signed TLS certificate created at $SSL_DIR"


echo "⬜ Setting up monthly certificate renewal with systemd..."
# Renewal script
sudo tee /usr/local/bin/renew-proxy-cert.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
SSL_DIR="/etc/ssl/kiwisdr"
TS=$(date +%F-%H%M%S)

# Backup old cert/key if they exist
if [[ -f "$SSL_DIR/kiwisdr.crt" ]]; then
  mv "$SSL_DIR/kiwisdr.crt" "$SSL_DIR/kiwisdr.crt.$TS"
fi
if [[ -f "$SSL_DIR/kiwisdr.key" ]]; then
  mv "$SSL_DIR/kiwisdr.key" "$SSL_DIR/kiwisdr.key.$TS"
fi

# Generate new cert
openssl req -x509 -nodes -days 90 \
  -subj "/C=DK/ST=Aarhus/L=Skyby/O=SkyTEM Surveys/OU=SkyTEM Surveys/CN=kiwisdr.local" \
  -newkey rsa:2048 \
  -keyout "$SSL_DIR/kiwisdr.key" \
  -out "$SSL_DIR/kiwisdr.crt"


# Cleanup old backups (keep only 3 newest of each)
# Enable nullglob so nonexistent files expand to nothing
shopt -s nullglob

crt_files=( "$SSL_DIR"/kiwisdr.crt.* )
if (( ${#crt_files[@]} > 3 )); then
    ls -1t "${crt_files[@]}" | tail -n +4 | xargs -r rm -f
fi

key_files=( "$SSL_DIR"/kiwisdr.key.* )
if (( ${#key_files[@]} > 3 )); then
    ls -1t "${key_files[@]}" | tail -n +4 | xargs -r rm -f
fi

# Reset nullglob to default (optional)
shopt -u nullglob


# Reload nginx to apply new cert
systemctl reload nginx
EOF
sudo chmod +x /usr/local/bin/renew-proxy-cert.sh

# Systemd service with logging
sudo tee /etc/systemd/system/proxy-cert-renew.service > /dev/null <<EOF
[Unit]
Description=Renew proxy self-signed SSL certificate

[Service]
Type=oneshot
ExecStart=/usr/local/bin/renew-proxy-cert.sh
StandardOutput=journal
StandardError=journal
EOF

# Systemd timer
sudo tee /etc/systemd/system/proxy-cert-renew.timer > /dev/null <<EOF
[Unit]
Description=Run proxy cert renewal monthly

# Midnight on the first day of every month
[Timer]
OnCalendar=*-*-01 00:00:00 
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
sudo systemctl daemon-reload
sudo systemctl enable proxy-cert-renew.timer
sudo systemctl start proxy-cert-renew.timer

echo "✅ Monthly certificate renewal via systemd is set up."
echo "ℹ️ To view certificate renewal logs: journalctl -u proxy-cert-renew.service"

# Custom 502 error page
sudo tee /var/www/html/502.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>502 Bad Gateway</title>
  <style>
    body {
      font-family: sans-serif;
      text-align: center;
      padding: 5%;
    }
    h1 {
      font-size: 3em;
    }
    p {
      font-size: 1.2em;
      margin: 1em 0;
    }
    button {
      padding: 0.6em 1.2em;
      font-size: 1em;
      border: none;
      border-radius: 8px;
      cursor: pointer;
    }

     /* Dark theme (default) */
    body {
      background-color: #1e1e1e;
      color: #f1f1f1;
    }
    h1 {
      color: #ff5555;
    }
    button {
      background-color: #444;
      color: #fff;
    }
    button:hover {
      background-color: #666;
    }

    /* Light theme (if system prefers light) */
    @media (prefers-color-scheme: light) {
      body {
        background-color: #f1f1f1;
        color: #1e1e1e;
      }
      h1 {
        color: #ff0000;
      }
      button {
        background-color: #ddd;
        color: #000;
      }
      button:hover {
        background-color: #bbb;
      }
    }
  </style>
  <script>
    // Auto-refresh every 10 seconds
    setTimeout(() => { window.location.reload(); }, 5000);
  </script>
</head>
<body>
  <h1>502 Bad Gateway</h1>  
  <p>The KiwiSDR WebUI isn’t responding right now.</p>
  <p>If You just booted the KiwiSDR, please wait.</p>
  <p>This page will auto-refresh.</p>
  <button onclick="window.location.reload();">Try Again Now</button>
</body>
</html>
EOF

# Recorder front end
sudo tee /var/www/html/recorder.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>KiwiRecorder Controller</title>
  <style>
    body { font-family: sans-serif; padding: 20px; background: #f0f0f0; }
    label { display: block; margin-top: 10px; }
    button { margin-top: 20px; padding: 10px 20px; }
  </style>
</head>
<body>
  <h1>KiwiRecorder Controller</h1>

  <label>
    Frequency (kHz):
    <input type="number" id="freq" value="15000" min="3000" max="30000">
  </label>

  <label>
    Bandwidth (Hz):
    <input type="number" id="bw" value="3000" min="100" max="32000">
  </label>

  <label>
    Duration (seconds):
    <input type="number" id="duration" value="60" min="1">
  </label>

  <button onclick="startRecording()">Start Recording</button>
  <button onclick="stopRecording()">Stop Recording</button>

  <div id="status"></div>

  <script>
    const statusDiv = document.getElementById('status');

    async function startRecording() {
      const freq = document.getElementById('freq').value;
      const bw = document.getElementById('bw').value;
      const duration = document.getElementById('duration').value;

      statusDiv.innerText = 'Starting recording...';

      try {
        const res = await fetch('/start', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ freq, bw, duration })
        });
        const data = await res.json();
        statusDiv.innerText = data.message;
      } catch (e) {
        statusDiv.innerText = 'Error: ' + e;
      }
    }

    async function stopRecording() {
      statusDiv.innerText = 'Stopping recording...';
      try {
        const res = await fetch('/stop', { method: 'POST' });
        const data = await res.json();
        statusDiv.innerText = data.message;
      } catch (e) {
        statusDiv.innerText = 'Error: ' + e;
      }
    }
  </script>
</body>
</html>
EOF

# Configure Nginx reverse proxy for kiwisdr.local
echo "⬜ Configuring Nginx Proxy for kiwisdr.local"
NGINX_CONF="/etc/nginx/sites-available/kiwisdr"
sudo tee "$NGINX_CONF" > /dev/null <<'EOF'
server {
    listen 80;
    server_name kiwisdr.local;
    return 301 https://\$host$request_uri;
}

server {
    listen 443 ssl;
    server_name kiwisdr.local;

    ssl_certificate     /etc/ssl/kiwisdr/kiwisdr.crt;
    ssl_certificate_key /etc/ssl/kiwisdr/kiwisdr.key;


    #ssl_protocols       TLSv1.2 TLSv1.3; # Uncomment if TLSv1.3 is supported
    ssl_protocols       TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    server_tokens off;
    client_max_body_size 1M;  # KiwiSDR doesn’t need large uploads
    client_body_buffer_size 128k;

    # Custom error page
    error_page 502 /502.html;
    location = /502.html {
        root /var/www/html;
        internal;
    }

    location /recorder {
        root /var/www/html;
        internal;
        index recorder.html;
    }

    location / {
        proxy_pass http://127.0.0.1:8073;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        ## Security headers - Breaks KiwiSDR WebUI
        #add_header X-Frame-Options DENY;
        #add_header X-Content-Type-Options nosniff;
        #add_header Referrer-Policy no-referrer;
        #add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        #add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self';" always;
        #add_header X-Permitted-Cross-Domain-Policies none;

        # Gzip for UI assets
        gzip on;
        gzip_types text/plain text/css application/javascript application/json;
        gzip_proxied any;
        gzip_min_length 256;
    }
}
EOF

# Enable the site
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/kiwisdr

# Test configuration and reload Nginx
sudo nginx -t > /dev/null 2>&1
sudo systemctl reload nginx

echo "✅ Nginx is configured. Access KiwiSDR at https://kiwisdr.local"