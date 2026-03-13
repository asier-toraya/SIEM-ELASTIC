#!/bin/sh
set -eu

# Ensure needed dirs/files exist (the /var/log folder is bind-mounted).
mkdir -p /run/sshd /var/log
touch /var/log/auth.log /var/log/syslog

# Host keys (only if not present)
ssh-keygen -A >/dev/null 2>&1 || true

# Clean up stale rsyslog pidfiles left behind by container restarts.
for pidfile in /run/rsyslogd.pid /var/run/rsyslogd.pid; do
  [ -f "$pidfile" ] || continue
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    continue
  fi
  rm -f "$pidfile"
done

# Start rsyslog so sshd can write auth logs to /var/log/auth.log.
/usr/sbin/rsyslogd

# Run sshd in foreground
exec /usr/sbin/sshd -D

