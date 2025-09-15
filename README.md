To install nginx proxy:
```bash
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/public.key | gpg --import && \
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/nginx-proxy-setup.sh.asc -o nginx-proxy-setup.sh.asc && \
curl -fsSL https://raw.githubusercontent.com/Ultraegern/kiwisdr-conf/refs/heads/main/nginx-proxy-setup.sh -o nginx-proxy-setup.sh && \
gpg --verify install.sh.asc install.sh && \
bash install.sh
```
