# GigaClaw Agent — руководство по развёртыванию

AI-ассистент для Mattermost на базе OpenClaw + OpenRouter. Один контейнер
на пользователя, один общий Mattermost-бот.

## Архитектура

```
Host (VM или ноутбук)
├── Docker daemon
│   └── контейнер gigaclaw-<username>     ← один на пользователя
│       ├── openclaw gateway :18789
│       ├── шаблоны + скиллы запечены в образ (/opt/gigaclaw/)
│       ├── кастомный channel-плагин: /opt/gigaclaw/extensions/orchestrator-channel
│       └── workspace: bind mount /data/users/<username>/ → /root/.openclaw/
└── gigaclaw-orchestrator                  ← отдельный сервис
    (см. vibe-projects/services/gigaclaw-orchestrator)
    ├── MM WebSocket (один shared bot-токен)
    ├── маппит sender → контейнер по label gigaclaw.user=<name>
    ├── форвард /v1/responses с session-key в формате native MM
    ├── POST /push — outbound от контейнеров
    └── SQLite: пользователи + apply-requests + admin-команды
```

Контейнер сам **не подключается** к Mattermost: в его конфиге канала
`mattermost` нет вообще. Весь inbound идёт через оркестратор, весь outbound —
через кастомный channel-плагин `orchestrator` → `/push` оркестратора.
Токены (`MM_BOT_TOKEN`, `MM_BASE_URL`) передаются в контейнер через env
и используются скиллами напрямую для REST-вызовов.

Скиллы в образе: `mattermost` (REST утилиты), `atlassian` (Jira + Confluence
через PAT), `glab` (GitLab CLI), `himalaya` (IMAP/SMTP), `gog` (Google
Workspace).

## Требования

- Docker 20+
- Node.js 22+ (для оркестратора)
- Mattermost bot token (один shared для всего стенда)
- OpenRouter API-ключ (LLM + web search)
- Запущенный `gigaclaw-orchestrator`

## 1. Собрать образ (один раз)

```bash
git clone <repo>
cd gigaclaw
docker build -t gigaclaw:latest .
```

В образ запекаются: OpenClaw, `himalaya`, `gog`, `glab`, python-зависимости
для atlassian, шаблоны (`configs/`, `workspace/AGENTS.md`, `workspace/TOOLS.md`,
`workspace/USER.md.tpl`, `workspace/SOUL.md`, `workspace/BOOT.md`), все скиллы
(`workspace/skills/`), а также кастомный channel-плагин `orchestrator`
(`packages/openclaw-orchestrator-channel/`) с pre-built `dist/`.

## 2. Поднять оркестратор

См. `vibe-projects/services/gigaclaw-orchestrator/README.md` — там админ-
команды `/apply` / `/admin approve` через MM сами создают `.env.<user>` из
шаблона, вызывают Docker API и регистрируют пользователя.

Orchestrator ждёт в `USERS_ENV_DIR` эталонный `.env.template` — оттуда
копируется per-user `.env.<username>` на approve и патчится
`ADMIN_USERNAME` + `ADMIN_NAME`.

## 3. Эталонный `.env.template` для пользователей

Скопировать `.env.example` в `USERS_ENV_DIR/.env.template` и заполнить
shared-поля (токены, URL-ы, настройки моделей). На approve оркестратор
сделает per-user копию и подставит `ADMIN_USERNAME` + `ADMIN_NAME`.

Переменные:

| Переменная | Описание |
|---|---|
| `MM_BOT_TOKEN` | Токен shared MM-бота. Скиллы внутри контейнера используют его для REST-запросов к MM. |
| `MM_BASE_URL` | URL сервера Mattermost. |
| `OPENROUTER_API_KEY` | OpenRouter API-ключ (LLM + Perplexity web search). |
| `LLM_MODEL` | Модель OpenRouter для текста (например `z-ai/glm-4.7`). |
| `LLM_VISION_MODEL` | Модель OpenRouter для картинок (например `qwen/qwen3-vl-32b-instruct`). |
| `ADMIN_NAME`, `ADMIN_USERNAME` | Проставляются оркестратором на approve, в шаблоне не задавать. |
| `OPENCLAW_GATEWAY_TOKEN` | Shared токен доступа к OpenClaw Gateway (одинаковый у всех контейнеров — его же использует оркестратор для форварда в `/v1/responses`). |
| `PUBLIC_ORIGIN` | URL дашборда без слэша. |
| `CONTROL_UI_DISABLE_DEVICE_AUTH` | `true` только если дашборд по HTTP с публичного IP. |
| `EMAIL_ADDRESS`, `EMAIL_PASSWORD`, `IMAP_HOST`, `SMTP_HOST` | himalaya (email). |
| `JIRA_URL`, `CONFLUENCE_URL`, `GITLAB_HOST` | Корп. хосты (shared). |
| `JIRA_PAT_TOKEN` / `CONFLUENCE_PAT_TOKEN` / `GITLAB_TOKEN` | Оставить пустыми в шаблоне — бот сам попросит у пользователя через onboarding. |
| `GOG_KEYRING_PASSWORD`, `GOG_ACCOUNT` | Google Workspace (см. ниже). |
| `ORCHESTRATOR_URL` | Куда контейнер POST-ит outbound (например `http://host.docker.internal:18790`). |
| `ORCHESTRATOR_PUSH_SECRET` | Shared bearer, совпадает с `PUSH_SECRET` оркестратора. |

## Dashboard (опционально)

Каждый контейнер открывает OpenClaw Control UI на своём host-порту. Порт
выдаёт оркестратор, посмотреть — `docker ps --filter label=gigaclaw.user`
или через админ-команду оркестратора (когда появится `/admin list`).

**Auth — только токен.** Значение `OPENCLAW_GATEWAY_TOKEN` вставить в
поле «Gateway Token» в браузере, или сразу открыть URL с токеном в query
(тогда вводить ничего не надо и можно забукмаркать):

```
http://127.0.0.1:<port>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

**Device pairing:** локальный `127.0.0.1` авто-approved. Для HTTP с
публичного IP браузер может ругаться на «non-secure context» — временно
включить `CONTROL_UI_DISABLE_DEVICE_AUTH=true` либо развернуть HTTPS
через nginx.

## Google Workspace (скилл gog)

Требует OAuth-авторизации один раз на пользователя.

### Один раз — настроить OAuth-приложение в Google Cloud Console

1. [console.cloud.google.com](https://console.cloud.google.com) → создай проект
2. Включи API: Gmail, Drive, Docs, Sheets, Calendar
3. **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**
   → тип **Desktop app** → скачать `client_secret.json`
4. **APIs & Services → OAuth consent screen → Audience** → добавь email
   бота в **Test users** (или Publish для бессрочного токена)

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

Токены шифруются `GOG_KEYRING_PASSWORD`. Не меняй его — иначе токены
станут нечитаемыми.

## Устранение неполадок

**Бот не отвечает в MM** — посмотри логи оркестратора (он один на всех
пользователей) и логи контейнера:

```bash
docker logs -f gigaclaw-<username>
```

**Сбросить все сессии конкретного пользователя (свежий контекст)**

```bash
docker exec -it gigaclaw-<username> rm -rf /root/.openclaw/agents/main/sessions/
docker exec -it gigaclaw-<username> mkdir -p /root/.openclaw/agents/main/sessions/
```

**Полный сброс пользователя** (⚠️ удаляет память бота) — через
админ-команду оркестратора `/admin reset <user>` (когда появится).
