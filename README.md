# AdGuard Home DNS — production-ready Docker Compose

AdGuard Home + Nginx reverse proxy + Certbot (авто-renew SSL).

После первичной настройки (`./init.sh`) все последующие запуски через `docker compose up -d` полностью production-ready: HTTPS, DNS, blocklist, авто-обновление сертификата.

---

## Первичная настройка

```bash
git clone <repo> && cd adguard
./init.sh
```

Скрипт запросит:
- **Домен** (должен указывать на IP сервера, например `adguard.choomba.tech`)
- **Email** для Let's Encrypt
- **Логин и пароль** для веб-интерфейса AdGuard Home

Скрипт автоматически:
1. Сгенерирует конфиг AdGuard Home (без мастера настройки)
2. Запустит стек в HTTP-режиме
3. Выпустит SSL-сертификат через Certbot
4. Переключит nginx на HTTPS
5. Запустит всё в production-режиме

---

## Последующие запуски

```bash
docker compose up -d
```

Всё работает из коробки: HTTPS + DNS + blocklist + авто-renew сертификата каждые 12 часов.

---

## Проверка

```bash
# DNS
nslookup google.com <IP-сервера>

# HTTPS
curl -I https://<ваш-домен>
```

---

## Структура проекта

```
├── docker-compose.yml          # adguardhome + nginx + certbot
├── init.sh                     # первичная настройка (один раз)
├── nginx/
│   └── nginx.conf              # reverse proxy (генерируется init.sh)
├── adguard/
│   ├── conf/
│   │   └── AdGuardHome.yaml    # конфиг AdGuard (генерируется init.sh)
│   └── work/                   # данные (логи, статистика, кеш)
├── certbot/
│   ├── conf/                   # SSL-сертификаты Let's Encrypt
│   └── www/                    # ACME webroot
├── blocklists/
│   └── blocked_adguard.txt     # blocklist (формат ||domain^)
├── .env                        # переменные окружения
└── README.md
```

---

## Управление

| Действие | Команда |
|----------|---------|
| Запустить | `docker compose up -d` |
| Остановить | `docker compose stop` |
| Перезапустить | `docker compose restart` |
| Логи AdGuard | `docker compose logs -f adguardhome` |
| Логи nginx | `docker compose logs -f nginx` |
| Логи certbot | `docker compose logs -f certbot` |
| Удалить контейнеры | `docker compose down` |
| Принудительный renew SSL | `docker compose run --rm --entrypoint certbot certbot renew` |

---

## Смена пароля AdGuard Home

```bash
docker compose stop adguardhome

# Сгенерировать новый хеш
NEW_HASH=$(docker run --rm httpd:2-alpine htpasswd -nbB admin НОВЫЙ_ПАРОЛЬ | cut -d: -f2)

# Подставить в конфиг (замените СТАРЫЙ_ХЕШ на текущее значение из файла)
sed -i "s|password:.*|password: ${NEW_HASH}|" adguard/conf/AdGuardHome.yaml

docker compose start adguardhome
```

---

## Переменные окружения (.env)

| Переменная | По умолчанию | Назначение |
|------------|-------------|------------|
| `DNS_PORT` | 53 | Порт DNS на хосте |
| `HTTP_PORT` | 80 | Порт HTTP на хосте |
| `HTTPS_PORT` | 443 | Порт HTTPS на хосте |
| `TZ` | Europe/Moscow | Часовой пояс |

---

## Blocklist

Файл `blocklists/blocked_adguard.txt` содержит правила в формате `||domain^`.

Подключение в AdGuard Home:
- **Фильтрация → Пользовательские правила** — вставить содержимое
- Или **Фильтрация → DNS-фильтры** — добавить как локальный фильтр
