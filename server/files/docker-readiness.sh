#!/bin/sh

SUPERVISORCTL="/usr/bin/supervisorctl"

SUPERVISORCTLOPTS="-u dummy -p dummy"

COMPONENTS="${COMPONENTS:-php-fpm cron nginx workers}"

for i in $COMPONENTS ; do
  RUNNING=`( $SUPERVISORCTL $SUPERVISORCTLOPTS status $i | grep -c RUNNING ) || true`

  [ $RUNNING -ne 1 ] && exit 1
done

echo $COMPONENTS | grep -w -q php-fpm

if [ $? -eq 0 ] ; then
  /usr/local/bin/php-fpm-healthcheck

  [ $? -ne 0 ] && exit $?
fi

exit 0
