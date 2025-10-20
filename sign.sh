#!/bin/bash
set -e

# Check if --force was passed to the script
FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

sign() {
    local file="$1"
    local sig="${file}.asc"

    # If signature doesn't exist or file is newer, or the --force argument is passed, re-sign
    if [[ ! -f "$sig" || "$file" -nt "$sig" || "$FORCE" == true ]]; then
        gpg --batch --yes --armor --detach-sign --output "$sig" "$file"
        echo "✅ Signed $file"
    else
        echo "⏩ Skipped $file (no changes)"
    fi
}

sign cert/renew-cert.service
sign cert/renew-cert.timer
sign cert/renew-cert.sh

sign html/502.html
sign html/recorder.html
sign html/filebrowser.html
sign html/help.html
sign html/stylesheet.css

sign nginx/nginx-setup.sh
sign nginx/nginx.conf

sign recorder/kiwiclient/kiwiclient-setup.sh
sign recorder/backend/backend-setup.sh
sign recorder/backend/backend.service
sign recorder/backend/build/backend.armv7
sign recorder/backend/build/backend.aarch64
sign recorder/backend/build/backend.x86_64

sign setup.sh

sleep 3