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
