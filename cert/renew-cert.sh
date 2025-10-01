#!/bin/bash
set -euo pipefail
SSL_DIR="/etc/ssl/kiwisdr"
TS=$(date +%F-%H%M%S)

# Create SSL directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Backup old cert/key if they exist
if [[ -f "$SSL_DIR/kiwisdr.crt" ]]; then
  mv "$SSL_DIR/kiwisdr.crt" "$SSL_DIR/kiwisdr.crt.$TS"
fi
if [[ -f "$SSL_DIR/kiwisdr.key" ]]; then
  mv "$SSL_DIR/kiwisdr.key" "$SSL_DIR/kiwisdr.key.$TS"
fi

# Generate new cert
openssl req -x509 -nodes -days 90 \
  -subj "/C=DK/ST=Aarhus/L=Skyby/O=SkyTEM Surveys ApS/OU=SkyTEM Surveys ApS/CN=kiwisdr.local" \
  -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
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