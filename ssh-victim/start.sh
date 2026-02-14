#!/bin/sh
set -eu

# Ensure needed dirs/files exist (the /var/log folder is bind-mounted).
mkdir -p /run/sshd /var/log
touch /var/log/auth.log /var/log/syslog

# Host keys (only if not present)
ssh-keygen -A >/dev/null 2>&1 || true

# Start rsyslog (so sshd can write auth logs to /var/log/auth.log)
/usr/sbin/rsyslogd || true

# Run sshd in foreground
exec /usr/sbin/sshd -D

