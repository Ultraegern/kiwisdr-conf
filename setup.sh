#!/bin/bash

set -euo pipefail

PGP_FINGERPRINT="3CB2F77A8047BEDC"

verify_signature() {
  local file="$1"
  local file_asc="${file}.asc"

  echo "⬜ Verifying the signature of $file..."

  # Perform the signature verification
  local signature=$(gpg --verify "$file_asc" "$file" 2>&1)

  # Check the verification result. This is a basic check;
  # more robust checks might involve parsing the output of gpg --verify and
  # checking specific error codes.
  if grep -q "gpg: Good signature from" <<< "$signature" ; then
    echo "✅ Signature verified successfully."
    return 0 # Success
  else
    echo "❌ Error: Signature verification failed."
    echo "--- Verification Output ---"
    echo "$signature"
    echo "--- End Verification Output ---"
    return 1 # Failure
  fi
}
