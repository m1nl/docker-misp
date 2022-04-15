#!/bin/sh

set -u

ln -s /proc/$$/fd/1 /dev/docker-stdout
ln -s /proc/$$/fd/2 /dev/docker-stderr

REDIS_FQDN="${REDIS_FQDN:-redis}"

export SAVE_HANDLER="${SAVE_HANDLER:-redis}"
export SAVE_PATH="${SAVE_PATH:-tcp://$REDIS_FQDN:6379}"

export POST_MAX_SIZE="${POST_MAX_SIZE:-512M}"
export UPLOAD_MAX_FILESIZE="${UPLOAD_MAX_FILESIZE:-512M}"
export MAX_FILE_UPLOADS="${MAX_FILE_UPLOADS:-500}"
export MAX_EXECUTION_TIME="${MAX_EXECUTION_TIME:-300}"

NUM_CORES="`nproc --all`"

export PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-2048M}"
export PHP_MAX_CHILDREN="${PHP_MAX_CHILDREN:-$((NUM_CORES * 4 > 32 ? NUM_CORES * 8 : 32))}"
export PHP_START_SERVERS="${PHP_START_SERVERS:-$((NUM_CORES * 4))}"
export PHP_MIN_SPARE_SERVERS="${PHP_MIN_SPARE_SERVERS:-$((NUM_CORES * 2))}"
export PHP_MAX_SPARE_SERVERS="${PHP_MAX_SPARE_SERVERS:-$((NUM_CORES * 4))}"
export PHP_MAX_REQUESTS="${PHP_MAX_REQUESTS:-500}"

export REAL_IP_HEADER_NAME="${REAL_IP_HEADER_NAME:-X-Real-IP}"

ENVSUBST="/usr/bin/envsubst"

PHP_CONFIG_TEMPLATE_DIR="/php-config-templates"
PHP_CONFIG_DIR="/etc/php/7.4/fpm/conf.d/"

FPM_CONFIG_TEMPLATE="/fpm-config-template.conf"
FPM_CONFIG="/etc/php/7.4/fpm/php-fpm.conf"

NGINX_CONFIG_TEMPLATE_DIR="/nginx-config-templates"
NGINX_CONFIG_DIR="/etc/nginx/conf.d"

NGINX_VARS='$REAL_IP_HEADER_NAME'

bootstrap_php_config() {
  for PHP_CONFIG_TEMPLATE in ${PHP_CONFIG_TEMPLATE_DIR}/* ; do
    PHP_CONFIG_FILENAME="`basename $PHP_CONFIG_TEMPLATE`"
    $ENVSUBST < "$PHP_CONFIG_TEMPLATE" > "$PHP_CONFIG_DIR/$PHP_CONFIG_FILENAME"
  done

  $ENVSUBST < "$FPM_CONFIG_TEMPLATE"> "$FPM_CONFIG"
}

echo "[bootstrap] Bootstrapping PHP configuration" && bootstrap_php_config

bootstrap_nginx_config() {
  for NGINX_CONFIG_TEMPLATE in ${NGINX_CONFIG_TEMPLATE_DIR}/* ; do
    NGINX_CONFIG_FILENAME="`basename $NGINX_CONFIG_TEMPLATE`"
    $ENVSUBST "$NGINX_VARS" < "$NGINX_CONFIG_TEMPLATE" > "$NGINX_CONFIG_DIR/$NGINX_CONFIG_FILENAME"
  done
}

echo "[bootstrap] Bootstrapping NGINX configuration" && bootstrap_nginx_config

echo "[bootstrap] Updating CA certificates" && /usr/sbin/update-ca-certificates

################################################################################

export MISP_PATH="/var/www/MISP"
export MISP_APP_CONFIG_PATH="$MISP_PATH/app/Config"
export MISP_APP_TMP_PATH="$MISP_PATH/app/tmp"
export MISP_APP_LOGS_PATH="$MISP_APP_TMP_PATH/logs"

export MISP_USER="www-data"
export MISP_GROUP="www-data"

export MISP_CAKE_PATH="/var/www/MISP/app/Console/cake"
export MISP_CAKE_CMD="sudo -u $MISP_USER -g $MISP_GROUP $MISP_CAKE_PATH"

export MYSQL_HOST="${MYSQL_HOST:-db}"
export MYSQL_PORT="${MYSQL_PORT:-3306}"
export MYSQL_USER="${MYSQL_USER:-misp}"

export MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:-/run/secrets/mysql_misp_password}"
[ "a$MYSQL_PASSWORD_FILE" = "a" -o ! -f "$MYSQL_PASSWORD_FILE" ] && ( mkdir -p /run/secrets ; echo "example" > /run/secrets/mysql_misp_password )

export MYSQL_DATABASE="${MYSQL_DATABASE:-misp}"

export SYNCSERVERS="${SYNCSERVERS:-}"
export MISP_MODULES_URL="${MISP_MODULES_URL:-http://misp-modules}"
export WORKERS="${WORKERS:-1}"
export NOREDIR="${NOREDIR:-false}"
export SECURESSL="${SECURESSL:-false}"
export DISIPV6="${DISIPV6:-false}"
export CERTAUTH="${CERTAUTH:-off}"

if [ $# -gt 0 ] ; then
  COMMAND="$1"
  shift

  exec "$COMMAND" "$@"
  exit $?
fi

init_mysql() {
  MYSQL_CMD="mysql --defaults-extra-file=/etc/mysql_misp_password.ini -u $MYSQL_USER -P $MYSQL_PORT -h $MYSQL_HOST -r -N $MYSQL_DATABASE"

  isDBUp() {
    echo "SHOW STATUS" | $MYSQL_CMD 1> /dev/null
    echo $?
  }

  isDBInitDone () {
    echo "DESCRIBE attributes" | $MYSQL_CMD 1> /dev/null
    echo $?
  }

  sed -e "s/\(.*\)/\[client\]\npassword=\"\1\"/g" < $MYSQL_PASSWORD_FILE > /etc/mysql_misp_password.ini
  chmod 0600 /etc/mysql_misp_password.ini

  RETRY=100
  until [ $(isDBUp) -eq 0 -o $RETRY -le 0 ] ; do
    echo "[initialization] Warning: waiting for database to come up"
    sleep 5
    RETRY=$(( RETRY - 1))
  done

  if [ $RETRY -le 0 ]; then
    >&2 echo "[initalization] Error: could not connect to database on $MYSQL_HOST:$MYSQL_PORT"
    exit 1
  fi

  if [ $(isDBInitDone) -eq 0 ]; then
    echo "[initialization] Database has already been initialized"
  else
    echo "[initialization] Database has not been initialized, importing MySQL schema"
    $MYSQL_CMD < /var/www/MISP/INSTALL/MYSQL.sql
  fi
}

init_misp_files() {
  if [ ! -f /var/www/MISP/app/files/INIT ]; then
    cp -R /var/www/MISP/app/files.dist/* /var/www/MISP/app/files
    touch /var/www/MISP/app/files/INIT
  fi
}

init_misp_tmp() {
  if [ ! -f /var/www/MISP/app/tmp/INIT ]; then
    cp -R /var/www/MISP/app/tmp.dist/* /var/www/MISP/app/tmp
    touch /var/www/MISP/app/tmp/INIT
  fi
}

init_certificates() {
  if [ ! -f /etc/nginx/certs/cert.pem -o ! -f /etc/nginx/certs/key.pem ]; then
    cd /etc/nginx/certs
    openssl req -x509 -subj '/CN=localhost' -nodes -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365
  fi
}

if [ "$INIT" = "true" ]; then
  echo "[initialization] Setup MySQL" && init_mysql
  echo "[initialization] Setup MISP files dir" && init_misp_files
  echo "[initialization] Setup MISP tmp dir" && init_misp_tmp
  echo "[initialization] Ensure SSL certificates exist" && init_certificates
fi

################################################################################

init_misp_config() {
  echo "[configuration] Copy initial configuration from distribution package if needed"

  [ -f $MISP_APP_CONFIG_PATH/bootstrap.php ] || cp ${MISP_APP_CONFIG_PATH}.dist/bootstrap.default.php $MISP_APP_CONFIG_PATH/bootstrap.php
  [ -f $MISP_APP_CONFIG_PATH/database.php ] || cp ${MISP_APP_CONFIG_PATH}.dist/database.default.php $MISP_APP_CONFIG_PATH/database.php
  [ -f $MISP_APP_CONFIG_PATH/core.php ] || cp ${MISP_APP_CONFIG_PATH}.dist/core.default.php $MISP_APP_CONFIG_PATH/core.php
  [ -f $MISP_APP_CONFIG_PATH/config.php ] || cp ${MISP_APP_CONFIG_PATH}.dist/config.default.php $MISP_APP_CONFIG_PATH/config.php
  [ -f $MISP_APP_CONFIG_PATH/email.php ] || cp ${MISP_APP_CONFIG_PATH}.dist/email.php $MISP_APP_CONFIG_PATH/email.php
  [ -f $MISP_APP_CONFIG_PATH/routes.php ] || cp ${MISP_APP_CONFIG_PATH}.dist/routes.php $MISP_APP_CONFIG_PATH/routes.php

  echo "[configuration] Set DB user, password and host in database.php"

  sed -i "s/localhost/$MYSQL_HOST/" $MISP_APP_CONFIG_PATH/database.php
  sed -i "s/db\s*login/$MYSQL_USER/" $MISP_APP_CONFIG_PATH/database.php
  perl -pe 'BEGIN {open(my $fh, "<", $ENV{"MYSQL_PASSWORD_FILE"}); $r=<$fh>; chomp($r)} s/db\s*password/$r/ge' -i $MISP_APP_CONFIG_PATH/database.php
  sed -i "s/'database' => 'misp'/'database' => '$MYSQL_DATABASE'/" $MISP_APP_CONFIG_PATH/database.php

  echo "[configuration] Apply workaround for https://github.com/MISP/MISP/issues/5608"

  # Workaround for https://github.com/MISP/MISP/issues/5608
  if [ ! -f /var/www/MISP/PyMISP/pymisp/data/describeTypes.json ]; then
    mkdir -p /var/www/MISP/PyMISP/pymisp/data/
    ln -s /usr/local/lib/python3.9/dist-packages/pymisp/data/describeTypes.json /var/www/MISP/PyMISP/pymisp/data/describeTypes.json
  fi
}

init_resque() {
  sed -i "s/'host' => .*Redis server hostname/'host' => '$REDIS_FQDN', \/\/ Redis server hostname/" "/var/www/MISP/app/Plugin/CakeResque/Config/config.php"

  echo "[configuration] Change number of Resque workers"
  if [ $WORKERS -gt 1 ]; then
    sed -i "s/start (-n \d+ )?--interval/start -n $WORKERS --interval/" /var/www/MISP/app/Console/worker/start.sh
  else
    sed -i "s/start (-n \d+ )?--interval/start --interval/" /var/www/MISP/app/Console/worker/start.sh
  fi
}

sync_misp_files() {
  for DIR in $(ls /var/www/MISP/app/files.dist); do
    rsync -azh --delete "/var/www/MISP/app/files.dist/$DIR" "/var/www/MISP/app/files/"
  done
}

enforce_permissions() {
  set -x

  find /var/www/MISP -not -user www-data -exec chown www-data:www-data {} +
  find /var/www/MISP -perm 550 -type f -exec chmod 0550 {} + && find /var/www/MISP -perm 770 -type d -exec chmod 0770 {} +

  chmod -R g+ws /var/www/MISP/app/tmp
  chmod -R g+ws /var/www/MISP/app/files
  chmod -R g+ws /var/www/MISP/app/files/scripts/tmp
  chmod 0600 /var/www/MISP/app/Config/config.php /var/www/MISP/app/Config/database.php /var/www/MISP/app/Config/email.php

  set +x
}

setup_php_cake() {
  $MISP_CAKE_CMD Admin setSetting "MISP.redis_host" "$REDIS_FQDN"
  $MISP_CAKE_CMD Admin setSetting "MISP.baseurl" "$HOSTNAME"
  $MISP_CAKE_CMD Admin setSetting "MISP.python_bin" "$(which python3)"
  $MISP_CAKE_CMD Admin setSetting "MISP.ca_path" "/etc/ssl/certs/ca-certificates.crt" --force

  $MISP_CAKE_CMD Admin setSetting "Plugin.ZeroMQ_redis_host" "$REDIS_FQDN"
  $MISP_CAKE_CMD Admin setSetting "Plugin.ZeroMQ_enable" true

  $MISP_CAKE_CMD Admin setSetting "Plugin.Enrichment_services_enable" true
  $MISP_CAKE_CMD Admin setSetting "Plugin.Enrichment_services_url" "$MISP_MODULES_URL"

  $MISP_CAKE_CMD Admin setSetting "Plugin.Import_services_enable" true
  $MISP_CAKE_CMD Admin setSetting "Plugin.Import_services_url" "$MISP_MODULES_URL"

  $MISP_CAKE_CMD Admin setSetting "Plugin.Export_services_enable" true
  $MISP_CAKE_CMD Admin setSetting "Plugin.Export_services_url" "$MISP_MODULES_URL"

  $MISP_CAKE_CMD Admin setSetting "Plugin.Cortex_services_enable" false
}

echo "[configuration] Initialize MISP base config" && init_misp_config
i
echo "[configuration] Configure Resque" && init_resque

echo "[configuration] Synchronize MISP app files" && sync_misp_files

echo "[configuration] Enforce permissions for MISP directory" && enforce_permissions

echo "[configuration] Setup php-cake from ENV variables" && setup_php_cake

################################################################################

init_crontab() {
  CRON_LOG_FILE="$MISP_APP_LOGS_PATH/cron.log"

  cat << EOF > /etc/cron.d/misp
20 2 * * * www-data $MISP_CAKE_PATH Server cacheFeed "$CRON_USER_ID" all >$CRON_LOG_FILE 2>&1
30 2 * * * www-data $MISP_CAKE_PATH Server fetchFeed "$CRON_USER_ID" all >$CRON_LOG_FILE 2>&1

00 3 * * * www-data $MISP_CAKE_PATH Admin updateGalaxies >$CRON_LOG_FILE 2>&1
10 3 * * * www-data $MISP_CAKE_PATH Admin updateTaxonomies >$CRON_LOG_FILE 2>&1
20 3 * * * www-data $MISP_CAKE_PATH Admin updateWarningLists >$CRON_LOG_FILE 2>&1
30 3 * * * www-data $MISP_CAKE_PATH Admin updateNoticeLists >$CRON_LOG_FILE 2>&1
45 3 * * * www-data $MISP_CAKE_PATH Admin updateObjectTemplates >$CRON_LOG_FILE 2>&1

EOF

  if [ "a$SYNCSERVERS" != "a" ]; then
    TIME=0

    for SYNCSERVER in $SYNCSERVERS; do
      cat << EOF >> /etc/cron.d/misp
$TIME 0 * * * www-data $MISP_CAKE_PATH Server pull "$CRON_USER_ID" "$SYNCSERVER" >$CRON_LOG_FILE 2>&1
$TIME 1 * * * www-data $MISP_CAKE_PATH Server push "$CRON_USER_ID" "$SYNCSERVER" >$CRON_LOG_FILE 2>&1

EOF

      TIME=$((TIME+5))
    done
  fi
}

echo "[configuration] Configure crontab" && init_crontab

################################################################################

init_nginx() {
  if [ ! -e "/etc/nginx/sites-enabled/misp80" -o -L "/etc/nginx/sites-enabled/misp80" ]; then
    rm -f /etc/nginx/sites-enabled/misp80

    if [ ! -L "/etc/nginx/sites-enabled/misp80" -a "$NOREDIR" = "true" ]; then
      echo "[configuration] Disabling port 80 redirect"
      ln -s /etc/nginx/sites-available/misp80-noredir /etc/nginx/sites-enabled/misp80
    elif [ ! -L "/etc/nginx/sites-enabled/misp80" ]; then
      echo "[configuration] Enable Port 80 Redirect"
      ln -s /etc/nginx/sites-available/misp80 /etc/nginx/sites-enabled/misp80
    fi
  fi

  if [ ! -e "/etc/nginx/sites-enabled/misp" -o -L "/etc/nginx/sites-enabled/misp" ]; then
    rm -f /etc/nginx/sites-enabled/misp

    if [ "$SECURESSL" = "true" ]; then
      echo "[configuration] Using Secure SSL"
      ln -s /etc/nginx/sites-available/misp-secure /etc/nginx/sites-enabled/misp
    elif [ ! -L "/etc/nginx/sites-enabled/misp" ]; then
      echo "[configuration] Using Standard SSL"
      ln -s /etc/nginx/sites-available/misp /etc/nginx/sites-enabled/misp
    fi
  fi

  if [ "$SECURESSL" = "true" -a ! -f "/etc/nginx/certs/dhparams.pem" ]; then
    echo "[configuration] Building dhparams.pem"
    openssl dhparam -out /etc/nginx/certs/dhparams.pem 2048
  fi

  if [ "$CERTAUTH" = "optional" -o "$CERTAUTH" = "on" ]; then
    echo "[configuration] Enabling SSL certificate Authentication"
    grep -qF "fastcgi_param SSL_CLIENT_I_DN \$ssl_client_i_dn;" /etc/nginx/snippets/fastcgi-php.conf || echo "fastcgi_param SSL_CLIENT_I_DN \$ssl_client_i_dn;" >> /etc/nginx/snippets/fastcgi-php.conf
    grep -qF "fastcgi_param SSL_CLIENT_S_DN \$ssl_client_s_dn;" /etc/nginx/snippets/fastcgi-php.conf || echo "fastcgi_param SSL_CLIENT_S_DN \$ssl_client_s_dn;" >> /etc/nginx/snippets/fastcgi-php.conf
    grep -qF 'ssl_client_certificate' /etc/nginx/sites-enabled/misp || sed -i '/ssl_prefer_server_ciphers/a \\    ssl_client_certificate /etc/nginx/certs/ca.pem;' /etc/nginx/sites-enabled/misp
    grep -qF 'ssl_verify_client' /etc/nginx/sites-enabled/misp || sed -i "/ssl_prefer_server_ciphers/a \\    ssl_verify_client $CERTAUTH;" /etc/nginx/sites-enabled/misp

    echo "[configuration] Enabling Cert Auth Plugin - Don't forget to configure it (https://github.com/MISP/MISP/tree/2.4/app/Plugin/CertAuth, step 2)"
    sed -i "s/\/\/ CakePlugin::load('CertAuth');/CakePlugin::load('CertAuth');/" $MISP_APP_CONFIG_PATH/bootstrap.php
  fi

  if [ "$DISIPV6" = "true" ]; then
    echo "[configuration] Disabling IPv6"
    sed -i "s/listen \[\:\:\]/\#listen \[\:\:\]/" /etc/nginx/sites-enabled/misp80
    sed -i "s/listen \[\:\:\]/\#listen \[\:\:\]/" /etc/nginx/sites-enabled/misp
  fi
}

echo "[configuration] Configure nginx" && init_nginx

################################################################################

SUPERVISORCTL="/usr/bin/supervisorctl"
SUPERVISORD="/usr/bin/supervisord"

SUPERVISORCTLOPTS="-u dummy -p dummy"
SUPERVISORDOPTS="-c /etc/supervisord.conf"
SUPERVISORDPID="/var/run/supervisord.pid"

COMPONENTS="${COMPONENTS:-php-fpm cron nginx workers}"

reload() {
  $SUPERVISORCTL $SUPERVISORCTLOPTS reload
}

shutdown() {
  $SUPERVISORCTL $SUPERVISORCTLOPTS shutdown
}

trap reload 1
trap shutdown 2 15

$SUPERVISORD $SUPERVISORDOPTS

sleep 1 && kill -0 `cat $SUPERVISORDPID`

for i in $COMPONENTS ; do
  echo "[supervisor] Start component $i"
  $SUPERVISORCTL $SUPERVISORCTLOPTS start $i &
  sleep 1
done

EXITCODE=0

while (kill -0 `cat $SUPERVISORDPID 2> /dev/null` > /dev/null 2>&1) ; do
  sleep 5

  NUM_FATAL=`( $SUPERVISORCTL $SUPERVISORCTLOPTS status | grep -c FATAL ) || true`
  if [ $NUM_FATAL -gt 0 ] ; then
    echo "[supervisor] At least one required component stuck in FATAL state - exiting"
    EXITCODE=1
    shutdown
  fi
done

exit $EXITCODE
