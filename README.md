# AdGuard Home DNS за Nginx (Docker Compose)

Инфраструктура для развёртывания AdGuard Home в Docker с Nginx в качестве reverse proxy. После `docker compose up -d` без дополнительной настройки доступны:

- **http://\<server-ip\>** — веб-интерфейс AdGuard Home через Nginx  
- **DNS на порту 53** — запросы обрабатывает AdGuard Home  
- **Блок-лист** — каталог `./blocklists/` смонтирован в контейнер; файл `blocked_adguard.txt` можно заполнить доменами и подключить через веб-интерфейс AdGuard Home.

---

## Предварительные требования

- **Docker** (рекомендуется актуальная версия)
- **Docker Compose** (v2: команда `docker compose`, либо v1: `docker-compose`)
- Порты **53** (TCP и UDP), **80** и **443** свободны на хосте (или укажите другие в `.env`)

Проверка установки:

```bash
docker --version
docker compose version
```

---

## Запуск

1. Перейдите в каталог проекта:

   ```bash
   cd adguard-dns
   ```

2. Запустите сервисы (дополнительная настройка не требуется):

   ```bash
   docker compose up -d
   ```

3. Откройте в браузере **http://localhost** (или **http://IP-вашего-сервера**). При первом запуске пройдите мастер настройки AdGuard Home.

4. Укажите на клиентских устройствах или в роутере в качестве DNS-сервера **IP этого хоста** (порт 53 используется по умолчанию).

---

## Проверка работы DNS

Быстрая проверка с другой машины или с того же хоста:

```bash
nslookup google.com <IP-сервера>
```

Пример (если IP сервера 192.168.1.100):

```bash
nslookup google.com 192.168.1.100
```

Успешный ответ со списком адресов означает, что DNS на порту 53 отвечает.

---

## Как добавить блок-лист (blocklist)

1. Отредактируйте файл **`blocklists/blocked_adguard.txt`**: добавьте по одному домену на строку (или правила в формате Adblock, если используете их как пользовательские правила).

2. Каталог `blocklists/` смонтирован в контейнер AdGuard Home по пути `/opt/adguardhome/blocklists/`.

3. В веб-интерфейсе AdGuard Home:
   - **Фильтрация → Пользовательские правила** — вставьте домены или правила из `blocked_adguard.txt` (скопируйте содержимое вручную), либо  
   - **Фильтрация → Фильтры DNS** — добавьте новый фильтр и при необходимости используйте содержимое файла как источник правил.

4. После изменения `blocked_adguard.txt` перезагружать контейнеры не обязательно — достаточно обновить правила в веб-интерфейсе. При следующем запуске контейнера файл по-прежнему будет доступен внутри контейнера.

---

## Настройка SSL (HTTPS)

### Инструкция по Certbot (Let's Encrypt) — через Docker Compose (Ubuntu)

Можно не устанавливать `certbot` на хост. В `docker-compose.yml` уже добавлен сервис `certbot` (профиль `tools`) и webroot-каталог для ACME challenge.

#### 1. Подготовка

1. Убедитесь, что домен (например, `dns.example.com`) указывает на IP вашего сервера.
2. Поднимите основные сервисы:

```bash
docker compose up -d
```

#### 2. Выпуск первого сертификата (внутри Docker)

```bash
# Перейдите в каталог проекта
cd /path/to/adguard

# Выпуск сертификата через контейнер certbot (замените домен и e-mail)
docker compose --profile tools run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d dns.example.com \
  --email admin@example.com \
  --agree-tos --no-eff-email
```

Сертификаты будут сохранены в каталоге `nginx/certs/live/dns.example.com/` на хосте.

#### 3. Включение HTTPS в Nginx

1. В `nginx/nginx.conf` раскомментируйте HTTPS-блок (`server` на 443).
2. В этом блоке замените пути сертификатов на ваши (пример):

```nginx
ssl_certificate     /etc/nginx/certs/live/dns.example.com/fullchain.pem;
ssl_certificate_key /etc/nginx/certs/live/dns.example.com/privkey.pem;
```

3. При необходимости включите редирект HTTP -> HTTPS (раскомментируйте `return 301 ...` в блоке 80).
4. Примените конфиг:

```bash
docker compose restart nginx
```

#### 4. Продление сертификата (renew)

Периодически выполняйте:

```bash
docker compose --profile tools run --rm certbot renew --webroot -w /var/www/certbot
```

После успешного renew перезагрузите Nginx, чтобы он подхватил обновлённые сертификаты:

```bash
docker compose exec nginx nginx -s reload
```

Для Ubuntu можно добавить в cron (ежедневно в 03:00):

```bash
0 3 * * * cd /path/to/adguard && docker compose --profile tools run --rm certbot renew --webroot -w /var/www/certbot && docker compose exec -T nginx nginx -s reload
```

---

### Вариант 1: Let's Encrypt (certbot) — кратко

1. Выпустите сертификат через контейнер `certbot` (`docker compose --profile tools run --rm certbot certonly ...`).
2. Укажите корректные пути к сертификатам в HTTPS-блоке `nginx/nginx.conf`.
3. Раскомментируйте HTTPS-блок и (по желанию) редирект HTTP -> HTTPS.
4. Выполните `docker compose restart nginx`.

### Вариант 2: Свой сертификат

1. Положите в каталог **`nginx/certs/`** файлы:
   - **`fullchain.pem`** — сертификат (или цепочка сертификатов)
   - **`privkey.pem`** — приватный ключ

2. В **`nginx/nginx.conf`** раскомментируйте блок `server` для порта 443 (в нём уже указаны пути `/etc/nginx/certs/fullchain.pem` и `privkey.pem`). При необходимости измените имена файлов в директивах `ssl_certificate` и `ssl_certificate_key`.

3. Перезапустите Nginx:

   ```bash
   docker compose restart nginx
   ```

---

## Указание DNS-сервера на клиентских устройствах

- **Роутер:** в настройках DHCP или LAN укажите в качестве DNS-сервера IP хоста, где запущен Docker (порт 53 подставляется автоматически).
- **Windows:** Параметры → Сеть и Интернет → Ethernet/Wi‑Fi → свой адаптер → Изменить параметры адаптера → Свойства IPv4 → «Использовать следующие адреса DNS-серверов» → введите IP сервера.
- **macOS:** Системные настройки → Сеть → Дополнительно → DNS → добавьте IP сервера.
- **Android/iOS:** В настройках Wi‑Fi выберите сеть → Дополнительно (или «i») → DNS → вручную укажите IP сервера.
- **Linux:** В настройках сети (NetworkManager, systemd-resolved и т.п.) укажите DNS = IP сервера.

После этого трафик DNS будет идти на AdGuard Home (порт 53).

---

## Управление контейнерами

| Действие        | Команда |
|-----------------|--------|
| Остановить      | `docker compose stop` |
| Запустить снова | `docker compose start` |
| Перезапустить   | `docker compose restart` |
| Перезапустить только Nginx | `docker compose restart nginx` |
| Перезапустить только AdGuard Home | `docker compose restart adguardhome` |
| Логи (все сервисы) | `docker compose logs -f` |
| Логи AdGuard Home | `docker compose logs -f adguardhome` |
| Логи Nginx      | `docker compose logs -f nginx` |
| Остановить и удалить контейнеры (данные в `adguard/` и `blocklists/` остаются) | `docker compose down` |

---

## Переменные окружения (.env)

| Переменная           | Назначение | По умолчанию |
|----------------------|------------|--------------|
| `ADGUARD_WEB_PORT`   | Порт веб-интерфейса AdGuard внутри сети | 3000 |
| `DNS_PORT`           | Порт DNS на хосте | 53 |
| `HTTP_PORT`          | Порт HTTP на хосте | 80 |
| `HTTPS_PORT`         | Порт HTTPS на хосте | 443 |
| `TZ`                 | Часовой пояс контейнера AdGuard Home | Europe/Moscow |

Изменение портов в `.env` применяется после перезапуска: `docker compose down && docker compose up -d`.

---

## Структура проекта

```
adguard-dns/
├── docker-compose.yml    # сервисы adguardhome и nginx
├── nginx/
│   ├── nginx.conf        # конфиг Nginx (прокси на AdGuard :3000, gzip, таймауты, закомментированный SSL)
│   └── certs/            # сюда класть fullchain.pem и privkey.pem для HTTPS
├── adguard/
│   ├── work/             # данные AdGuard Home (логи, статистика, кэш фильтров)
│   └── conf/             # конфиг AdGuard Home (создаётся при первом запуске)
├── blocklists/
│   └── blocked_adguard.txt  # свой список блокировки (дополните и настройте в веб-интерфейсе)
├── .env                  # переменные окружения
└── README.md
```

Данные в `adguard/conf` и `adguard/work` сохраняются между перезапусками и после `docker compose down`.

### Что хранится в adguard/conf и adguard/work

**adguard/conf** — конфигурация:

- **AdGuardHome.yaml** — основной конфиг: настройки DNS, веб-интерфейса, фильтров, upstream-серверов, клиентов и т.д. Создаётся при первом запуске. Редактировать вручную можно только при остановленном контейнере, иначе изменения перезапишутся.

**adguard/work** — данные:

- **data/** — каталог данных:
  - лог DNS-запросов (например, `querylog.json`);
  - **filters/** — скачанные файлы фильтров (блок-листы); при обновлении могут сохраняться старые копии (например, с суффиксом `.old`).
- **stats.db** — база статистики (объём может достигать нескольких МБ).
- **sessions.db** — данные сессий (обычно десятки КБ).

Оба каталога нужно учитывать при бэкапах и не удалять при обновлении образа.
