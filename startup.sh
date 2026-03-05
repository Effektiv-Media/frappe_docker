#!/bin/bash

cd /home/frappe/frappe-bench

# Check if site already exists in the database
SITE_EXISTS=$(mysql -h "$MYSQLHOST" -u root -p"$MYSQL_ROOT_PASSWORD" \
  -e "SHOW DATABASES LIKE '_78cfa5efeb514aa4';" 2>/dev/null | grep -c "_78cfa5efeb514aa4")

if [ "$SITE_EXISTS" -eq 0 ]; then
  echo "First boot - creating site..."
  bench new-site signello \
    --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
    --admin-password "$MYSQL_ROOT_PASSWORD" \
    --db-host "$MYSQLHOST" \
    --db-port 3306 \
    --mariadb-user-host-login-scope='%' \
    --force

  bench --site signello install-app erpnext
  bench --site signello install-app signello_2
fi

# Always run these on every boot
bench use signello
echo "signello" > sites/currentsite.txt
echo '{"serve_default_site": true, "default_site": "signello"}' > sites/common_site_config.json
bench --site signello set-config host_name "https://$HOST_NAME"
ln -sf /home/frappe/frappe-bench/sites/signello /home/frappe/frappe-bench/sites/$HOST_NAME

# Run migrations in case of new code
bench --site signello migrate

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