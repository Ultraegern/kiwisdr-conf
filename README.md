# Overview
This repo installs and configues:
* Nginx as a TLS endpoint, webserver for static files, and a proxy for everything else
* KiwiClient as a tool for recording from the Kiwi
* Rust + Actix Web as a webserver for exposing KiwiClient as a REST api 
### Compatability
Oficial .img files are [here](http://kiwisdr.com/quickstart/index.html#id-dload).  
This repo is known to work with
* KiwiSDR 1 + BeagleBone Green + [This firmware](http://kiwisdr.com/files/KiwiSDR_v1.804_BBG_BBB_Debian_11.11.img.xz) SHA256: `2f60798f60b647f0b18f8ac7493776c7b75f22f17977dffdd6c8253274538c3f`

# Installation Instructions

### Change password and connect with `ssh`:
Go to the KiwiSDR Admin Panel
[http://kiwisdr.local:8073/admin](http://kiwisdr.local:8073/admin)  (Note: `http`, not `https`)  
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
ssh debian@kiwisdr.local
```
Switch user
```bash
su
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
> ℹ️ **Note:** The TLS cert is Self-Signed, so your browser may complain. That is normal.

### Customise
Go to the [Admin Panel](https://kiwisdr.local/admin)  
Go to the `Webpage` tab  
Top bar title: `KiwiSDR by SkyTEM Surveys ApS`  
Owner info: [Copy this file](https://github.com/Ultraegern/kiwisdr-conf/blob/main/skytem-logo.html)  
Grid square: Continuous update from GPS: `true`  
Location: Continuous update from GPS: `Hi Res`  
Admin email: `it@skytem.com`  
