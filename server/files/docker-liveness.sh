#!/bin/sh

set -e

SUPERVISORCTL="/usr/bin/supervisorctl"

SUPERVISORCTLOPTS="-u dummy -p dummy"

COMPONENTS="${COMPONENTS:-php-fpm cron nginx workers}"

NUM_FATAL=`( $SUPERVISORCTL $SUPERVISORCTLOPTS status | grep -c FATAL ) || true`

[ $NUM_FATAL -gt 0 ] && exit 1

echo $COMPONENTS | grep -w -q php-fpm

if [ $? -eq 0 ] ; then
  /usr/local/bin/php-fpm-healthcheck

  [ $? -ne 0 ] && exit $?
fi

exit 0
