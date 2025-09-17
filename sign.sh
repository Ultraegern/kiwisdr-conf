#!/bin/bash

gpg --batch --yes --armor --detach-sign --output nginx-setup.sh.asc nginx-setup.sh
gpg --batch --yes --armor --detach-sign --output kiwiclient-setup.sh.asc kiwiclient-setup.sh
