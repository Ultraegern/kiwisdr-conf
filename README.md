Start by adding public.key to your keyring:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/public.key | gpg --import
```
Mark the key as trusted (Only if you actualy trust the key):
```bash
echo "3CB2F77A8047BEDC:4:" | gpg --import-ownertrust >/dev/null
```
> ⚠️ **Warning:** Only mark a key as trusted if you trust the person the key belongs to, and that the key is actualy the persons key (eg. somebody hacked github and replaced the key with there key).

Download the repository and run setup.sh:
```bash
curl -fsSL https://github.com/Ultraegern/kiwisdr-conf/archive/refs/heads/main.zip -o /tmp/kiwisdr-conf.zip && \
unzip /tmp/kiwisdr-conf.zip -d /tmp/kiwisdr-conf && \
cd /tmp/kiwisdr-conf && \
gpg --verify setup.sh.asc setup.sh 2>/dev/null && \
./setup.sh
```
