Installation Instructions
==============

Start by adding public.key to your keyring:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/public.key | gpg --import
```
Mark the key as trusted (Only if you actualy trust the key):
```bash
echo "3CB2F77A8047BEDC:4:" | gpg --import-ownertrust >/dev/null
```
> ⚠️ **Warning:** Only mark a key as trusted if you trust the person the key belongs to, and that the key is actually that person's key (eg. somebody hacked Github and replaced the key with their key).

Download the repository and run setup.sh:
```bash
curl -fsSL https://github.com/Ultraegern/kiwisdr-conf/archive/refs/heads/main.zip -o /tmp/kiwisdr-conf.zip && \
sudo apt install unzip -qq 1>/dev/null && \
unzip -qq /tmp/kiwisdr-conf.zip -d /tmp/ && \
rm /tmp/kiwisdr-conf.zip && \
mv /tmp/kiwisdr-conf-main /tmp/kiwisdr-conf && \
cd /tmp/kiwisdr-conf && \
gpg --verify setup.sh.asc setup.sh 2>/dev/null && \
sudo chmod +x setup.sh && \
sudo ./setup.sh
```
