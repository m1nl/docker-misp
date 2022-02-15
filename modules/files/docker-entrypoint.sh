#!/bin/sh

set -eu

ln -s /proc/$$/fd/1 /dev/docker-stdout
ln -s /proc/$$/fd/2 /dev/docker-stderr

echo "[bootstrap] Updating CA certificates" && /usr/sbin/update-ca-certificates

export REDIS_BACKEND="${REDIS_FQDN:-redis}"

if [ $# -gt 0 ] ; then
  COMMAND="$1"
  shift

  exec "$COMMAND" "$@"
  exit $?
fi
