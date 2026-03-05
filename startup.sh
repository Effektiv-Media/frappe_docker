#!/bin/bash
cd /home/frappe/frappe-bench

if [ ! -d "sites/signello" ]; then
  echo "Creating site..."
  bench new-site signello \
    --mariadb-root-password $MYSQL_ROOT_PASSWORD \
    --admin-password $ADMIN_PASSWORD \
    --db-host $MYSQLHOST \
    --db-port $MYSQLPORT \
    --no-mariadb-socket

  bench --site signello install-app erpnext
  bench --site signello install-app signello_2
  bench use signello
  bench --site signello set-config host_name $HOST_NAME
  bench set-config -g serve_default_site true
fi

exec gunicorn \
  --chdir=/home/frappe/frappe-bench/sites \
  --bind=0.0.0.0:8000 \
  --threads=4 \
  --workers=2 \
  --worker-class=gthread \
  --timeout=120 \
  frappe.app:application