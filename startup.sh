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

# Always run on every boot
bench use signello
echo "signello" > sites/currentsite.txt
echo '{"serve_default_site": true, "default_site": "signello"}' > sites/common_site_config.json
bench --site signello set-config host_name "https://$HOST_NAME"
ln -sf /home/frappe/frappe-bench/sites/signello /home/frappe/frappe-bench/sites/$HOST_NAME

bench --site signello migrate
bench --site signello build --force

# Write nginx config
cat > /etc/nginx/conf.d/frappe.conf << 'EOF'
upstream frappe {
    server 127.0.0.1:8000;
}

server {
    listen 80;
    server_name _;

    root /home/frappe/frappe-bench/sites;

    location /assets {
        try_files $uri =404;
    }

    location ~ ^/files/.*.(htm|html|svg|xml) {
        add_header Content-disposition "attachment";
        try_files $uri =404;
    }

    location /files {
        try_files $uri =404;
    }

    location / {
        proxy_pass http://frappe;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120;
    }
}
EOF

# Start nginx in background
nginx -g 'daemon off;' &

# Start gunicorn in foreground
exec /home/frappe/frappe-bench/env/bin/gunicorn \
  --chdir=/home/frappe/frappe-bench/sites \
  --bind=127.0.0.1:8000 \
  --threads=4 \
  --workers=2 \
  --worker-class=gthread \
  --worker-tmp-dir=/dev/shm \
  --timeout=120 \
  --preload \
  frappe.app:application