#!/bin/bash

gpg --batch --yes --armor --detach-sign --output nginx-setup.sh.asc nginx-setup.sh
