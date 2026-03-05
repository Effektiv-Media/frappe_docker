#!/bin/bash

cd /home/frappe/frappe-bench

bench new-site signello \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
  --admin-password "$MYSQL_ROOT_PASSWORD" \
  --db-host "$MYSQLHOST" \
  --db-port 3306 \
  --mariadb-user-host-login-scope='%' \
  --force

bench --site signello install-app erpnext
bench --site signello install-app signello_2
bench use signello
bench --site signello set-config host_name "$HOST_NAME"
echo '{"serve_default_site": true}' > sites/common_site_config.json

exec /home/frappe/frappe-bench/env/bin/gunicorn \
  --chdir=/home/frappe/frappe-bench/sites \
  --bind=0.0.0.0:8000 \
  --threads=4 \
  --workers=2 \
  --worker-class=gthread \
  --worker-tmp-dir=/dev/shm \
  --timeout=120 \
  --preload \
  frappe.app:application