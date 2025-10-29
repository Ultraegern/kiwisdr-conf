#!/bin/bash
set -euo pipefail
SSL_DIR="/etc/ssl/kiwisdr"
CA_DIR="$SSL_DIR/ca"
TS=$(date +%F-%H%M%S)
HOST="kiwisdr.local"

mkdir -p "$SSL_DIR" "$CA_DIR"

# ----------------------------------------------------------------------
# 1. Create KiwiCA (EC P-256) if not present
# ----------------------------------------------------------------------
if [[ ! -f "$CA_DIR/KiwiCA.key" || ! -f "$CA_DIR/KiwiCA.pem" ]]; then
  echo "Creating new EC (P-256) local CA: KiwiCA"
  # Generate EC private key for CA (P-256)
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$CA_DIR/KiwiCA.key"
  chmod 600 "$CA_DIR/KiwiCA.key"

  # Self-sign CA certificate (10 years)
  openssl req -x509 -new -key "$CA_DIR/KiwiCA.key" \
    -sha256 -days 3650 \
    -subj "/C=DK
    /ST=Aarhus
    /L=Skyby
    /O=SkyTEM Surveys ApS
    /OU=Local Development CA
    /CN=KiwiCA" \
    -out "$CA_DIR/KiwiCA.pem"
  chmod 644 "$CA_DIR/KiwiCA.pem"
else
  echo "Using existing KiwiCA"
fi

# ----------------------------------------------------------------------
# 2. Create OpenSSL config for SAN (temporary file)
# ----------------------------------------------------------------------
CONF_FILE=$(mktemp)
cat > "$CONF_FILE" <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
C = DK
ST = Aarhus
L = Skyby
O = SkyTEM Surveys ApS
OU = SkyTEM Surveys ApS
CN = ${HOST}

[ server_cert ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer

# Optional fields showing corporate identity
certificatePolicies = 1.3.6.1.4.1.12345.1.1
subject:organizationIdentifier = US-TX-987654321

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${HOST}
IP.1  = 10.42.0.99
EOF

# ----------------------------------------------------------------------
# 3. Generate server EC key and CSR (P-256) in one step
# ----------------------------------------------------------------------
# Use -newkey ec -pkeyopt to generate EC key and CSR together.
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -nodes -keyout "$SSL_DIR/kiwisdr.key" -out "$SSL_DIR/kiwisdr.csr" \
  -config "$CONF_FILE"

chmod 600 "$SSL_DIR/kiwisdr.key"

# ----------------------------------------------------------------------
# 4. Sign CSR with KiwiCA (produce server cert)
# ----------------------------------------------------------------------
# Use CA's EC key/cert to sign. -CAcreateserial will create KiwiCA.srl next to CA cert.
openssl x509 -req -in "$SSL_DIR/kiwisdr.csr" \
  -CA "$CA_DIR/KiwiCA.pem" -CAkey "$CA_DIR/KiwiCA.key" \
  -CAcreateserial -out "$SSL_DIR/kiwisdr.crt" \
  -days 90 -sha256 -extfile "$CONF_FILE" -extensions req_ext

# tighten permissions
chmod 644 "$SSL_DIR/kiwisdr.crt"

# remove temporary CSR and config
rm -f "$SSL_DIR/kiwisdr.csr" "$CONF_FILE"

# ----------------------------------------------------------------------
# 5. Reload nginx to apply new cert (best-effort)
# ----------------------------------------------------------------------
systemctl reload nginx || echo "⚠️  Warning: Failed to reload nginx. Please reload it manually."

echo "✅ New server certificate installed at: $SSL_DIR/kiwisdr.crt"
echo "✅ Local CA is: $CA_DIR/KiwiCA.pem"
echo
echo "ℹ️ To trust the chain in browsers/OS, import $CA_DIR/KiwiCA.pem into your OS/browser trust store."
