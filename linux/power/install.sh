#!/bin/sh
set -eu
cd "$(dirname "$0")"
install -d /usr/local/sbin /etc/systemd/system
install -m 755 akali-pl1.sh /usr/local/sbin/akali-pl1.sh
install -m 644 akali-pl1.service /etc/systemd/system/akali-pl1.service
systemctl daemon-reload
systemctl enable akali-pl1.service
# enable --now does not re-run a oneshot that is already active.
systemctl restart akali-pl1.service
systemctl is-enabled akali-pl1.service
systemctl is-active akali-pl1.service
