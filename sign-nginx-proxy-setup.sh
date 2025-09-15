#!/bin/bash

gpg --batch --yes --armor --detach-sign --output nginx-proxy-setup.sh.asc nginx-proxy-setup.sh
