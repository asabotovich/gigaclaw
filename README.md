# GigaClaw Agent — руководство по развёртыванию

AI-ассистент для Mattermost на базе OpenClaw + OpenRouter. Per-user контейнеры, управление через TS CLI (`clawfarm`), который напрямую вызывает Docker API (прото для будущего Orchestrator, см. `.claude/docs/gigaclaw-roadmap.md`).

## Архитектура

```
Host (VM или ноутбук)
├── Docker daemon
│   └── контейнер gigaclaw-<username>   ← один на пользователя
│       ├── openclaw gateway :18789
│       ├── шаблоны + скиллы запечены в образ (/opt/gigaclaw/)
│       └── workspace: bind mount /data/users/<username>/  → /root/.openclaw/
└── orchestrator/          ← TS CLI (dockerode), аналог будущего Orchestrator
    clawfarm add-user / list / logs / reset / remove
```

Скиллы в образе: `mattermost`, `atlassian` (Jira + Confluence через PAT), `glab` (GitLab CLI), `himalaya` (IMAP/SMTP), `gog` (Google Workspace).

## Требования

- Docker 20+
- Node.js 18+ (для CLI)
- Mattermost bot token
- OpenRouter API-ключ (LLM + web search)

## Установка

### 1. Собрать образ (один раз)

```bash
git clone <repo>
cd gigaclaw
docker build -t gigaclaw:latest .
```

В образ запекаются: OpenClaw, himalaya, gog, glab, python-зависимости для atlassian, шаблоны (`configs/`, `workspace/AGENTS.md`, `workspace/TOOLS.md`, `workspace/USER.md.tpl`), все скиллы (`workspace/skills/`).

### 2. Подготовить `.env` для пользователя

```bash
cp .env.example .env.asabotovich
# заполнить токены
```

Переменные:

| Переменная | Описание |
|---|---|
| `MM_BOT_TOKEN` | Токен бота в Mattermost |
| `MM_BASE_URL` | URL сервера Mattermost |
| `OPENROUTER_API_KEY` | OpenRouter API-ключ (LLM + Perplexity web search) |
| `LLM_MODEL` | Модель OpenRouter (например `z-ai/glm-4.7`) |
| `ADMIN_NAME` | Имя владельца (для `USER.md`) |
| `ADMIN_USERNAME` | Mattermost login владельца (используется в allowlist) |
| `OPENCLAW_GATEWAY_TOKEN` | Токен доступа к Dashboard (`openssl rand -hex 32`) |
| `PUBLIC_ORIGIN` | URL дашборда без слэша (например `http://46.243.142.210`) |
| `CONTROL_UI_DISABLE_DEVICE_AUTH` | `true` только если дашборд по HTTP с публичного IP |
| `EMAIL_ADDRESS`, `EMAIL_PASSWORD`, `IMAP_HOST`, `SMTP_HOST` | himalaya (email) |
| `JIRA_URL`, `JIRA_PAT_TOKEN` | корп. Jira (если есть доступ) |
| `CONFLUENCE_URL`, `CONFLUENCE_PAT_TOKEN` | корп. Confluence |
| `GITLAB_HOST`, `GITLAB_TOKEN` | корп. GitLab (scopes: `read_api`, `read_repository`) |
| `GOG_KEYRING_PASSWORD`, `GOG_ACCOUNT` | Google Workspace (см. ниже) |

### 3. Установить CLI (один раз)

```bash
cd orchestrator
npm install
npm link                     # создаст /usr/local/bin/clawfarm → ./bin/clawfarm.js
```

Теперь команда `clawfarm` доступна глобально из любой директории. После `git pull`
пересобирать ничего не надо — shim fallback'ится на `ts-node` и подхватывает свежий код.

Без `npm link` можно использовать `clawfarm <...>` из `orchestrator/`.

**Автодополнение в zsh** (опционально, но приятно):

```bash
# Добавь эти две строки в ~/.zshrc, подставь реальный путь к репо:
echo "fpath=($PWD/completions \$fpath)" >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc
```

После этого: `clawfarm <TAB>` выдаёт список команд, `clawfarm logs <TAB>` —
список активных пользователей (из docker labels), `--env <TAB>` — `.env*` файлы.

### 4. Поднять бота

```bash
clawfarm add-user asabotovich --env ../.env.asabotovich
```

`add-user` делает:
1. **provision** — one-shot контейнер, `envsubst`-ом рендерит шаблоны из образа в `/data/users/<username>/`
2. **create + start** — runtime-контейнер с bind mount на ту же директорию, env из `.env`

## Управление

```bash
cd orchestrator

# Список всех ботов
clawfarm list

# Логи
clawfarm logs asabotovich -f

# Остановить / запустить (данные сохраняются)
clawfarm stop asabotovich
clawfarm start asabotovich

# Пересоздать контейнер (после смены токена или обновления образа)
#   workspace/ переживает reset — только AGENTS.md/TOOLS.md перезаписываются,
#   USER.md и memory/ остаются
clawfarm reset asabotovich --env ../.env.asabotovich

# Удалить бота (контейнер)
clawfarm remove asabotovich
#   директория /data/users/asabotovich/ остаётся — очистить вручную если нужно
```

### Массовый апгрейд образа

Для обновления **всех** пользователей на новую версию образа есть хелпер в корне репозитория:

```bash
# Пересобрать и обновить всех на свежий gigaclaw:latest
docker build -t gigaclaw:latest .
./upgrade.sh

# Или указать конкретный тег из registry
docker pull registry/gigaclaw:v1.2.3
./upgrade.sh registry/gigaclaw:v1.2.3
```

Скрипт проходит по всем контейнерам с меткой `gigaclaw.user=<name>` и для каждого
делает `clawfarm reset <user> --env ../.env.<user>`. Данные (`memory/`, `agents/`,
`openclaw.json` с токенами) переживают пересоздание. Это прото того, что в проде
станет `POST /admin/upgrade` из Orchestrator (роадмап, задача 6.1).

### Переменные окружения CLI

| Переменная | Дефолт | Для чего |
|---|---|---|
| `GIGACLAW_IMAGE` | `gigaclaw:latest` | Docker image tag |
| `GIGACLAW_DATA_ROOT` | `/data/users` | Где хранить per-user данные на хосте |
| `GIGACLAW_BASE_PORT` | `18789` | Стартовый порт для выдачи контейнерам |

## Dashboard (опционально)

Каждый контейнер открывает OpenClaw Control UI на своём host-порту (посмотреть — `clawfarm list`).

**Auth: только токен.** Значение `OPENCLAW_GATEWAY_TOKEN` из `.env` вставить в поле `Gateway Token` в браузере — запомнится на сессию браузера.

Можно сразу открыть URL с токеном в query (тогда вводить ничего не надо и можно забукмаркать):
```
http://127.0.0.1:<port>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

**Device pairing:** локальный `127.0.0.1` авто-approved. Для HTTP с публичного IP браузер может ругаться на «non-secure context» — временно включить `CONTROL_UI_DISABLE_DEVICE_AUTH=true` либо развернуть HTTPS через nginx.

## Google Workspace (скилл gog)

Требует OAuth-авторизации один раз на пользователя.

### Один раз — настроить OAuth-приложение в Google Cloud Console

1. [console.cloud.google.com](https://console.cloud.google.com) → создай проект
2. Включи API: Gmail, Drive, Docs, Sheets, Calendar
3. **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID** → тип **Desktop app** → скачать `client_secret.json`
4. **APIs & Services → OAuth consent screen → Audience** → добавь email бота в **Test users** (или Publish для бессрочного токена)

### Авторизация бота

```bash
# 1. Положить client_secret.json в data dir пользователя
mkdir -p /data/users/asabotovich/.gog
cp client_secret.json /data/users/asabotovich/.gog/

# 2. Выдать client_secret в gog (внутри контейнера)
docker exec -it gigaclaw-asabotovich \
  gog auth credentials /root/.openclaw/.gog/client_secret.json

# 3. Шаг 1 — получить ссылку
docker exec -it gigaclaw-asabotovich \
  gog auth add you@gmail.com --remote --step 1 --services all

# Открыть ссылку в браузере, разрешить доступ, скопировать URL редиректа.

# 4. Шаг 2 — обменять code на токен
docker exec -it gigaclaw-asabotovich \
  gog auth add you@gmail.com --remote --step 2 \
  --services gmail,calendar,drive,docs,sheets \
  --auth-url 'http://127.0.0.1:XXXXX/oauth2/callback?...'
```

Токены шифруются `GOG_KEYRING_PASSWORD`. Не меняй его — иначе токены станут нечитаемыми.

## Устранение неполадок

**Бот не отвечает в MM**
```bash
clawfarm logs asabotovich | tail -50
```

**Сбросить все сессии (свежий контекст)**
```bash
docker exec -it gigaclaw-asabotovich rm -rf /root/.openclaw/agents/main/sessions/
docker exec -it gigaclaw-asabotovich mkdir -p /root/.openclaw/agents/main/sessions/
```

**Полный сброс пользователя** (⚠️ удаляет память бота)
```bash
clawfarm remove asabotovich
rm -rf /data/users/asabotovich
clawfarm add-user asabotovich --env ../.env.asabotovich
```

**Обновить образ**
```bash
docker build -t gigaclaw:latest .
# пересоздать всех пользователей на новом образе:
clawfarm reset asabotovich --env ../.env.asabotovich
```

## Маппинг на будущий Orchestrator (роадмап)

| Сейчас (прото) | В проде (роадмап) |
|---|---|
| `clawfarm add-user` | `/admin add-user` → `createContainer(user)` (задача 2.3) |
| `clawfarm reset` | `reset(user)` (задача 2.3, триггерится после `/connect`) |
| `clawfarm remove` / `stop` | `/admin remove` / `/admin suspend` (задача 3.1) |
| `clawfarm list` | `/admin list-users` (задача 3.1) |
| `.env.<user>` файлы | Postgres `credentials`, шифрование `VAULT_KEY` (задача 2.6) |
| `dockerode` по unix socket | `dockerode` по SSH/mTLS до ClawFarm VM (задача 1.3) |
| `envsubst` в `provision` | то же самое, скрипт без изменений |
