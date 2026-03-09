#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --- Nginx config for HTTP-only mode (before certificate is issued) ---
write_http_only_nginx() {
    cat > nginx/nginx.conf <<NGINXEOF
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    resolver 127.0.0.11 valid=10s ipv6=off;

    server {
        listen 80;
        server_name ${DOMAIN};

        location ^~ /.well-known/acme-challenge/ {
            root /var/www/certbot;
            allow all;
            default_type "text/plain";
        }

        location / {
            set \$adguard_upstream adguardhome:3000;
            proxy_pass http://\$adguard_upstream;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
NGINXEOF
}

# --- Nginx config for production (HTTPS + redirect) ---
write_production_nginx() {
    cat > nginx/nginx.conf <<NGINXEOF
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    resolver 127.0.0.11 valid=10s ipv6=off;

    server {
        listen 80;
        server_name ${DOMAIN};

        location ^~ /.well-known/acme-challenge/ {
            root /var/www/certbot;
            allow all;
            default_type "text/plain";
        }

        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name ${DOMAIN};

        ssl_certificate     /etc/nginx/ssl/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/live/${DOMAIN}/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;

        location / {
            set \$adguard_upstream adguardhome:3000;
            proxy_pass http://\$adguard_upstream;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_connect_timeout 60s;
            proxy_read_timeout 86400s;
        }
    }
}
NGINXEOF
}

echo "========================================="
echo " AdGuard Home — первичная настройка"
echo "========================================="
echo ""

# --- Ввод параметров ---
read -rp "Домен (например adguard.choomba.tech): " DOMAIN
read -rp "Email для Let's Encrypt: " EMAIL
read -rp "Логин AdGuard Home [admin]: " AG_USER
AG_USER="${AG_USER:-admin}"
read -rsp "Пароль AdGuard Home: " AG_PASS
echo ""

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$AG_PASS" ]; then
    echo "Ошибка: все поля обязательны."
    exit 1
fi

echo ""
echo ">>> Генерация хеша пароля..."
PASSWORD_HASH=$(docker run --rm httpd:2-alpine htpasswd -nbB "$AG_USER" "$AG_PASS" | cut -d: -f2)

echo ">>> Подготовка каталогов..."
mkdir -p adguard/conf adguard/work certbot/www certbot/conf nginx blocklists

# --- AdGuardHome.yaml ---
echo ">>> Генерация AdGuardHome.yaml..."
sed "s|__ADGUARD_PASSWORD_HASH__|${PASSWORD_HASH}|g" adguard/conf/AdGuardHome.yaml > adguard/conf/AdGuardHome.yaml.tmp
sed -i "s|name: admin|name: ${AG_USER}|g" adguard/conf/AdGuardHome.yaml.tmp
mv adguard/conf/AdGuardHome.yaml.tmp adguard/conf/AdGuardHome.yaml

# --- nginx.conf (HTTP-only для выпуска сертификата) ---
echo ">>> Настройка nginx (HTTP-режим для выпуска сертификата)..."
write_http_only_nginx

# --- Запуск стека ---
echo ">>> Запуск стека (HTTP-режим)..."
docker compose up -d adguardhome nginx

echo ">>> Ожидание запуска nginx (5 сек)..."
sleep 5

# --- Выпуск сертификата ---
echo ">>> Выпуск SSL-сертификата через Certbot..."
docker compose run --rm --entrypoint certbot certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    -d "$DOMAIN"

# --- Проверка сертификата ---
if [ ! -f "certbot/conf/live/${DOMAIN}/fullchain.pem" ]; then
    echo ""
    echo "ОШИБКА: сертификат не был создан."
    echo "Проверьте, что домен ${DOMAIN} указывает на IP этого сервера и порт 80 открыт."
    exit 1
fi

# --- Переключение на production nginx (HTTPS) ---
echo ">>> Переключение nginx на HTTPS..."
write_production_nginx

# --- Запуск всего стека ---
echo ">>> Перезапуск стека (production)..."
docker compose up -d

echo ""
echo "========================================="
echo " Готово!"
echo "========================================="
echo ""
echo " HTTPS:  https://${DOMAIN}"
echo " DNS:    ${DOMAIN}:53"
echo " Логин:  ${AG_USER}"
echo ""
echo " Последующие запуски: docker compose up -d"
echo "========================================="
