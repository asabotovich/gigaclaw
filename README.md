# OpenClaw Agent — Руководство по развёртыванию

AI-ассистент для Mattermost на базе OpenClaw + GigaChat.

## Архитектура

```
VM
├── Docker
│   ├── openclaw   — агент, gateway на порту 18789 (только localhost)
│   │   └── himalaya установлен внутри контейнера
│   └── gpt2giga   — прокси OpenAI→GigaChat на порту 8090 (внутренний)
└── systemd не нужен
```

## Требования

- Docker + Docker Compose
- Аккаунт бота в Mattermost и токен
- Credentials GigaChat API
- Email-аккаунт (IMAP/SMTP)

## Установка

### 1. Клонируй репозиторий

```bash
git clone https://git.sberdevices.ru/sberdevices-frontend/vibe-projects.git
cd vibe-projects/services/openclaw-agent
```

### 2. Задай переменные окружения (через `.env`)

Скопируй пример и заполни своими значениями:

```bash
cp .env.example .env
```

Переменные:

| Переменная | Описание |
|---|---|
| `MM_BOT_TOKEN` | Токен бота Mattermost |
| `MM_BASE_URL` | URL сервера Mattermost |
| `GIGACHAT_CREDENTIALS` | Credentials GigaChat в формате Base64 |
| `GIGACHAT_BASE_URL` | URL API GigaChat |
| `GIGACHAT_AUTH_URL` | URL для получения токена GigaChat |
| `EMAIL_ADDRESS` | Email-адрес бота |
| `EMAIL_PASSWORD` | Пароль / app-password от почты |
| `IMAP_HOST` | IMAP-сервер почты |
| `SMTP_HOST` | SMTP-сервер почты |
| `ADMIN_NAME` | Имя администратора (для `USER.md`) |
| `ADMIN_USERNAME` | Логин администратора в Mattermost |
| `GATEWAY_PASSWORD` | Пароль для доступа к Dashboard |
| `PUBLIC_ORIGIN` | URL дашборда **без слэша в конце** (например `http://46.243.142.210` за nginx). Иначе ошибка `origin not allowed` |
| `CONTROL_UI_DISABLE_DEVICE_AUTH` | `true` только если дашборд открываешь по **HTTP с публичного IP** (иначе браузер: *device identity / secure context*). В проде лучше **HTTPS** и `false` |
| `OPENROUTER_API_KEY` | API-ключ OpenRouter для поиска в интернете через Perplexity |

### 3. Запусти установщик

```bash
./install.sh
```

Установщик выполнит:
1. Подстановку переменных во все шаблоны конфигов
2. Сборку Docker-образа openclaw
3. Запуск всех сервисов через `docker compose up`

## Что генерируется при установке

Все сгенерированные конфиги кладутся в каталог `build/` (он добавлен в `.gitignore`):

```
openclaw-agent/
├── build/
│   ├── openclaw.json         ← конфиг OpenClaw, монтируется в контейнер
│   ├── .env.gpt2giga         ← конфиг gpt2giga
│   ├── himalaya-config.toml  ← конфиг email
│   └── AGENTS.md             ← с подставленным списком админов
└── workspace/                ← шаблон воркспейса, используется только при первом запуске
```

Файлы воркспейса (память бота, дневные логи) хранятся в Docker named volume `openclaw_workspace` (`/root/.openclaw/workspace` в контейнере) и сохраняются при перезапуске контейнера.

## Доступ для администраторов

Пользователи из `ADMIN_USERNAME` могут:
- Выполнять shell-команды
- Читать почтовый ящик
- Обращаться к файлам на диске

Обычные пользователи могут только общаться и отправлять письма.

### Обновление списка администраторов

1. Задай обновлённый `ADMIN_USERNAME`
2. Перезапусти `./install.sh` — конфиги пересгенерируются и применятся к контейнеру

### Полный сброс (⚠️ удаляет память бота)

```bash
docker compose down -v
./install.sh
```

## Доступ к Dashboard и pairing

### URL и пароль

- Админ‑панель доступна локально по адресу: `http://127.0.0.1:18789/`
- Тип авторизации: **password**
- Пароль задаётся в `.env` переменной `GATEWAY_PASSWORD` (например `12345`)

Чтобы зайти:

1. Открой в браузере `http://127.0.0.1:18789/`
2. Введи пароль из `GATEWAY_PASSWORD` в поле **Password**
3. Нажми **Connect**

### Первое подключение и pairing

При первом подключении нового браузера может появиться сообщение `pairing required`. Это защита по устройствам.

1. В терминале (в каталоге `openclaw-agent`) посмотри pending‑запросы:

```bash
docker compose exec openclaw openclaw devices list
```

2. Найди строку в блоке `Pending`, скопируй `Request` (UUID), например:

```text
0f276ecf-1780-4f59-853e-1c14cbfa3447
```

3. Одобри устройство:

```bash
  0f276ecf-1780-4f59-853e-1c14cbfa3447
```

После approve браузер считается доверенным устройством. В дальнейшем достаточно вводить только пароль.

### Как сбросить доверенные устройства

Если нужно отозвать все ранее одобренные браузеры:

```bash
docker compose exec openclaw \
  openclaw devices clear --yes \
  --password "$GATEWAY_PASSWORD" \
  --url ws://127.0.0.1:18789
```

После этого следующий вход вновь потребует pairing.

## Google Workspace (скилл gog)

Бот умеет работать с Gmail, Google Drive, Docs, Sheets, Calendar через скилл `gog`. Скилл встроен в OpenClaw — дополнительно устанавливать ничего не нужно.

### Что нужно сделать один раз

#### 1. Создать OAuth-приложение в Google Cloud Console

1. Открой [console.cloud.google.com](https://console.cloud.google.com) и создай проект
2. Включи нужные API: Gmail API, Google Drive API, Google Docs API, Google Sheets API, Google Calendar API
3. Перейди в **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**
4. Тип приложения: **Desktop app**
5. Скачай JSON — это и есть `client_secret.json`
6. Перейди в **APIs & Services → OAuth consent screen → Audience**
7. Добавь нужные email-адреса в **Test users** (или переведи приложение в Production для бессрочного токена)

#### 2. Добавить переменные в `.env`

```bash
GOG_KEYRING_PASSWORD=придумай-пароль   # ключ шифрования токенов
GOG_ACCOUNT=you@gmail.com              # Google-аккаунт бота
```

#### 3. Скопировать `client_secret.json` на сервер

```bash
# Создаёт install.sh автоматически, но на всякий случай:
mkdir -p data/gog

scp client_secret.json user@server:/path/to/gigaclaw/data/gog/client_secret.json
```

#### 4. Задать credentials и авторизоваться

```bash
# Записать client_secret в credentials.json (внутри контейнера)
docker compose exec openclaw \
  gog auth credentials /root/.config/gogcli/client_secret.json

# Шаг 1 — получить ссылку для авторизации
docker compose exec -T -e GOG_KEYRING_PASSWORD=<пароль> openclaw \
  gog auth add you@gmail.com --remote --step 1 --services all
```

Открой выданную ссылку в браузере, войди в Google-аккаунт, разреши доступ.  
После редиректа браузер попытается открыть `http://127.0.0.1:XXXXX/...` — страница не откроется, **это нормально**.  
Скопируй полный URL из адресной строки.

```bash
# Шаг 2 — обменять code на токен (вставь скопированный URL)
docker compose exec -T -e GOG_KEYRING_PASSWORD=<пароль> openclaw \
  gog auth add you@gmail.com --remote --step 2 \
  --services gmail,calendar,chat,classroom,drive,docs,slides,contacts,tasks,sheets,people,forms,appscript \
  --auth-url 'http://127.0.0.1:XXXXX/oauth2/callback?...'
```

#### 5. Проверить что всё работает

```bash
docker compose exec -T openclaw gog drive ls -a you@gmail.com
```

### Как хранятся токены

```
data/gog/                          ← bind mount, живёт на диске сервера
├── client_secret.json             ← ты скопировал вручную
├── credentials.json               ← создал gog auth credentials
└── keyring/
    └── token:you@gmail.com        ← зашифрованный refresh token
```

Токены шифруются паролем `GOG_KEYRING_PASSWORD`. Папка `data/gog/` переживает любой редеплой — повторная авторизация не нужна.

> **Важно:** не меняй `GOG_KEYRING_PASSWORD` после авторизации — токены станут нечитаемыми, придётся авторизоваться заново.

### Бессрочный токен

По умолчанию OAuth-приложение в режиме **Testing** выдаёт токены на 7 дней.  
Чтобы получить бессрочный refresh token — переведи приложение в **Production**:

1. [console.cloud.google.com/apis/credentials/consent](https://console.cloud.google.com/apis/credentials/consent)
2. Нажми **Publish app → Confirm**
3. Пройди авторизацию заново (`gog auth add ... --force-consent`)

## Управление

```bash
# Логи
docker compose logs -f openclaw
docker compose logs -f gpt2giga

# Перезапуск бота
docker compose restart openclaw

# Остановить всё
docker compose down

# Обновить openclaw до последней версии
docker compose build --no-cache openclaw
docker compose up -d openclaw
```

## Устранение неполадок

**Бот не отвечает в MM**
```bash
docker compose logs openclaw | tail -50
```

**Проблемы с подключением к GigaChat**
```bash
docker compose logs gpt2giga | tail -20
```

**Сбросить все сессии (свежий контекст)**
```bash
docker compose exec openclaw rm -rf /root/.openclaw/agents/main/sessions/
docker compose exec openclaw mkdir -p /root/.openclaw/agents/main/sessions/
```
