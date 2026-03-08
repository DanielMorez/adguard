# AdGuard Home DNS за Nginx (Docker Compose)

Готовая инфраструктура для AdGuard Home с Nginx reverse proxy и Certbot в составе `docker-compose`.

После `docker compose up -d` работает:

- `http://<server-ip>` — веб-интерфейс AdGuard Home через Nginx
- DNS-запросы на порт `53` (TCP/UDP) — обрабатывает AdGuard Home
- blocklist из `./blocklists/blocked_adguard.txt` доступен внутри контейнера

---

## Предварительные требования

- Docker
- Docker Compose
- Домен (например, `adguard.choomba.tech`) с A-записью на IP вашего сервера
- Свободные порты: `53/tcp`, `53/udp`, `80`, `443`

---

## Запуск

```bash
docker compose up -d
```

Проверка DNS:

```bash
nslookup google.com <IP-сервера>
```

---

## SSL через Certbot внутри Docker Compose

### 1) Текущий `nginx.conf` работает по HTTP

В конфиге уже есть блок для challenge:

- `location /.well-known/acme-challenge/` -> `/var/www/certbot`

Это нужно для верификации домена Let's Encrypt.

### 2) Получить сертификат

```bash
docker compose run --rm certbot certonly   --webroot   --webroot-path=/var/www/certbot   --email your@email.com   --agree-tos   --no-eff-email   -d adguard.choomba.tech
```

Сертификаты появятся на хосте в каталоге:

- `./certbot/conf/live/adguard.choomba.tech/`

### 3) Включить HTTPS

В `nginx/nginx.conf`:

1. Раскомментируйте HTTPS-блок `server { listen 443 ssl; ... }`
2. Убедитесь, что пути сертификатов такие:
   - `/etc/nginx/ssl/live/adguard.choomba.tech/fullchain.pem`
   - `/etc/nginx/ssl/live/adguard.choomba.tech/privkey.pem`
3. (Опционально) включите редирект HTTP -> HTTPS в HTTP-блоке

Примените изменения:

```bash
docker compose restart nginx
```

### 4) Автообновление сертификатов

Сервис `certbot` в `docker-compose.yml` уже настроен на `renew` каждые 12 часов.

Проверить вручную:

```bash
docker compose run --rm certbot renew --webroot -w /var/www/certbot
```

После успешного renew перезагрузить nginx:

```bash
docker compose exec nginx nginx -s reload
```

---

## Blocklist

1. Добавьте домены в `blocklists/blocked_adguard.txt` (по одному на строку)
2. В AdGuard Home подключите список через фильтрацию (пользовательские правила или DNS-фильтры)

---

## Управление

```bash
docker compose stop
docker compose start
docker compose restart
docker compose logs -f
docker compose logs -f adguardhome
docker compose logs -f nginx
docker compose down
```

---

## Переменные окружения (`.env`)

- `ADGUARD_WEB_PORT=3000`
- `DNS_PORT=53`
- `HTTP_PORT=80`
- `HTTPS_PORT=443`
- `TZ=Europe/Moscow`

---

## Что хранится в каталогах

- `adguard/conf` — конфигурация (`AdGuardHome.yaml` и т.д.)
- `adguard/work` — данные (querylog, filters, статистика, сессии)
- `certbot/www` — webroot для проверки домена (`http-01`)
- `certbot/conf` — сертификаты Let's Encrypt
