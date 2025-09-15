To install nginx proxy:
```bash
curl -fsSL https://raw.githubusercontent.com/user/repo/main/public.key | gpg --import && \
curl -fsSL https://raw.githubusercontent.com/user/repo/main/install.sh.asc -o install.sh.asc && \
curl -fsSL https://raw.githubusercontent.com/user/repo/main/install.sh -o install.sh && \
gpg --verify install.sh.asc install.sh && \
bash install.sh
```
