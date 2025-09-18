#!/bin/bash

set -euo pipefail

PGP_KEY_FINGERPRINT="3CB2F77A8047BEDC"

verify_signature() {
  local file="$1"
  local file_asc="${file}.asc"

  echo "⬜ Verifying the signature of $file..."

  local gpg_output=$(gpg --verify --keyring=- --fingerprint "$file_asc" "$file" 2>&1)
  # Check the verification result. This is a basic check;
  # more robust checks might involve parsing the output of gpg --verify and
  # checking specific error codes.
  if grep -q "gpg: Good signature from " <<< "$gpg_output"; then
    echo "✅ Signature verified successfully for $file."
    return 0 # Success
  else
    echo "❌ Error: Signature verification failed for $file."
    echo "ℹ️ --- Verification Output ---"
    echo "$gpg_output"
    echo "ℹ️ --- End Verification Output ---"
    return 1 # Failure
  fi
}

verify_signature nginx/nginx-setup.sh && ./nginx/nginx-setup.sh

rm -R /tmp/kiwisdr-conf