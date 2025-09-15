To install nginx proxy:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/public.key | gpg --import && \
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/nginx-proxy-setup.sh.asc -o install.sh.asc && \
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/nginx-proxy-setup.sh -o install.sh && \
gpg --verify install.sh.asc install.sh && \
bash install.sh
```
