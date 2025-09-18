#!/bin/bash

gpg --batch --yes --armor --detach-sign --output cert/renew-cert.service.asc cert/renew-cert.service
gpg --batch --yes --armor --detach-sign --output cert/renew-cert.timer.asc cert/renew-cert.timer
gpg --batch --yes --armor --detach-sign --output cert/renew-cert.sh.asc cert/renew-cert.sh

gpg --batch --yes --armor --detach-sign --output html/502.html.asc html/502.html
gpg --batch --yes --armor --detach-sign --output html/recorder.html.asc html/recorder.html

gpg --batch --yes --armor --detach-sign --output nginx/nginx-setup.sh.asc nginx/nginx-setup.sh
gpg --batch --yes --armor --detach-sign --output nginx/nginx.conf.asc nginx/nginx.conf

gpg --batch --yes --armor --detach-sign --output /recorder/kiwiclient/kiwiclient-setup.sh.asc /recorder/kiwiclient/kiwiclient-setup.sh

gpg --batch --yes --armor --detach-sign --output setup.sh.asc setup.sh
