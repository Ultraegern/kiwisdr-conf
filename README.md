# Overview
This repo installs and configues:
* Nginx as a TLS endpoint, webserver for static files, and a proxy for everything else
* KiwiClient as a tool for recording from the Kiwi
* Python 3.9 + Flask as a webserver for exposing KiwiClient as a REST api 

# Installation Instructions

### Change password and connect with `ssh`:
Go to [http://kiwisdr.local:8073/admin](http://kiwisdr.local:8073/admin)  (Note: `http`, not `https`)  
Go to the `Security` tab  
Edit `Admin password`  
Go to the `Console` tab  
Press the `Connect` button

Chage the password of the root user:
```bash
passwd root
```
Chage the password of the debian user:
```bash
passwd debian
```
Now you can `ssh` into the Kiwi (from a terminal on you laptop, not the Kiwi web console)
```shell
ssh root@kiwisdr.local
```

### Add key
Add public.key to your keyring:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/public.key | gpg --import
```
Mark the key as trusted (Only if you actualy trust the key):
```bash
gpg --import-ownertrust <<< "846475029CE00982F700C9AC3CB2F77A8047BEDC:3:"
```
> ⚠️ **Warning:** Only mark a key as trusted if you trust the person the key belongs to, and that the key is actually that person's key (eg. somebody hacked Github and replaced the key with their key).

### Install
Download the repository and run setup.sh:
```bash
curl -fsSL https://github.com/Ultraegern/kiwisdr-conf/archive/refs/heads/main.zip -o /tmp/kiwisdr-conf.zip && \
sudo apt install unzip -qq 1>/dev/null && \
unzip -qq /tmp/kiwisdr-conf.zip -d /tmp/ && \
rm /tmp/kiwisdr-conf.zip && \
cd /tmp/kiwisdr-conf-main && \
gpg --verify setup.sh.asc setup.sh 2>/dev/null && \
sudo chmod +x setup.sh && \
sudo ./setup.sh
```

Now you can go to [https://kiwisdr.local/help](https://kiwisdr.local/help)
