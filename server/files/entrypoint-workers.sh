#!/bin/sh

while true; do
    echo "[workers] Starting"
    sudo -u www-data -g www-data /var/www/MISP/app/Console/worker/start.sh
    echo "[workers] Started"

    sleep 3600
done
