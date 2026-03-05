#!/bin/bash

cd /home/frappe/frappe-bench

# Always recreate site folder (--force reuses existing DB without wiping data)
bench new-site signello \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
  --admin-password "$MYSQL_ROOT_PASSWORD" \
  --db-host "$MYSQLHOST" \
  --db-port 3306 \
  --mariadb-user-host-login-scope='%' \
  --force

# Only install apps if not already installed
ERPNEXT_INSTALLED=$(mysql -h "$MYSQLHOST" -u root -p"$MYSQL_ROOT_PASSWORD" \
  -D "_78cfa5efeb514aa4" \
  -e "SELECT name FROM tabModule WHERE name='ERPNext';" 2>/dev/null | grep -c "ERPNext")

if [ "$ERPNEXT_INSTALLED" -eq 0 ]; then
  echo "Installing apps..."
  bench --site signello install-app erpnext
  bench --site signello install-app signello_2
fi

bench use signello
echo "signello" > sites/currentsite.txt

cat > sites/common_site_config.json << EOF
{
  "serve_default_site": true,
  "default_site": "signello",
  "redis_cache": "$REDIS_CACHE",
  "redis_queue": "$REDIS_QUEUE",
  "redis_socketio": "$REDIS_CACHE"
}
EOF

bench --site signello set-config host_name "https://$HOST_NAME"
ln -sf /home/frappe/frappe-bench/sites/signello /home/frappe/frappe-bench/sites/$HOST_NAME

bench --site signello migrate
bench --site signello build --force

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

nginx -g 'daemon off;' &

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