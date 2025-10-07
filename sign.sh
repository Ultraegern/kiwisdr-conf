#!/bin/bash

sign () {
    local file="$1"
    gpg --batch --yes --armor --detach-sign --output "${file}.asc" "$file"
    echo "✅ Signed $file"
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
sign recorder/webui-backend/backend-setup.sh
sign recorder/webui-backend/backend.service
sign recorder/webui-backend/backend.py

sign setup.sh
