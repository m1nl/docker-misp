#!/bin/sh

# update ca-certificates
/usr/sbin/update-ca-certificates

COMMAND="$1"
shift

exec "$COMMAND" "$@"
exit $?
