#!/bin/sh

rand() {
  od -vN "$1" -An -tx1 /dev/urandom | tr -d " \n"
}

[ -d .secrets ] || mkdir .secrets
chmod 0700 .secrets

[ -f .secrets/mysql_misp_password ] || rand 16 > .secrets/mysql_misp_password
[ -f .secrets/mysql_root_password ] || rand 16 > .secrets/mysql_root_password
