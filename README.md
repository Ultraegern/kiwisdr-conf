Start by adding public.key to GPG:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/public.key | gpg --import
```
And mark it as trusted:
```bash
echo "3CB2F77A8047BEDC:4:" | gpg --import-ownertrust >/dev/null
```
> ⚠️ **Warning:** Only trust keys from sources you verify. Running scripts signed by an unverified key could compromise your system.

Install and configure nginx as a proxy for KiwiSDR WebUI and a webserver for KiwiRecorder:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/nginx-proxy-setup.sh.asc -o nginx-proxy-setup.sh.asc && \
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/nginx-proxy-setup.sh -o nginx-proxy-setup.sh && \
KEYID=$(gpg --with-colons --import-options show-only --import nginx-proxy-setup.sh.asc 2>/dev/null | awk -F: '/^pub:/ {print $5}') && \
TRUST=$(gpg --list-keys --with-colons $KEYID 2>/dev/null | awk -F: '/^pub:/ {print $2}') && \
run_script() { gpg --verify nginx-proxy-setup.sh.asc nginx-proxy-setup.sh >/dev/null 2>&1 && echo "✅ GPG verification passed. Running script..." && bash nginx-proxy-setup.sh || { echo "❌ GPG verification failed! Aborting."; exit 1; }; } && \
if [[ "$TRUST" == "u" || "$TRUST" == "f" ]]; then run_script; else read -p "⚠️ Key not fully trusted. Run script anyway? [y/N] " yn; [[ "$yn" =~ ^[Yy]$ ]] && run_script || { echo "Aborted."; exit 1; }; fi
```

Install and configure KiwiClient:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/kiwiclient-setup.sh.asc -o nginx-proxy-setup.sh.asc && \
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/kiwiclient-setup.sh -o nginx-proxy-setup.sh && \
KEYID=$(gpg --with-colons --import-options show-only --import kiwiclient-setup.sh.asc 2>/dev/null | awk -F: '/^pub:/ {print $5}') && \
TRUST=$(gpg --list-keys --with-colons $KEYID 2>/dev/null | awk -F: '/^pub:/ {print $2}') && \
run_script() { gpg --verify kiwiclient-setup.sh.asc kiwiclient-setup.sh >/dev/null 2>&1 && echo "✅ GPG verification passed. Running script..." && bash kiwiclient-setup.sh || { echo "❌ GPG verification failed! Aborting."; exit 1; }; } && \
if [[ "$TRUST" == "u" || "$TRUST" == "f" ]]; then run_script; else read -p "⚠️ Key not fully trusted. Run script anyway? [y/N] " yn; [[ "$yn" =~ ^[Yy]$ ]] && run_script || { echo "Aborted."; exit 1; }; fi
```

