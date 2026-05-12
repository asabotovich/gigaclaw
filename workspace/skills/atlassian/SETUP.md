# Atlassian — настройка (walkthrough)

> ⚠️ **Настроить нужно ТОЛЬКО ТОКЕН.**
> URL, host, SSL-флаги уже лежат в `/root/.openclaw/openclaw.json`.
>
> - **НЕ переспрашивай** их у пользователя.
> - **НЕ упоминай** URL в сообщениях («URL уже настроен: …» — мусор,
>   пользователь и так знает, в какую Jira логинится).
> - **НЕ отчитывайся** о промежуточных шагах (типа «прочитал конфиг»,
>   «сохранил поле»). Пользователь видит результат в конце, не ход твоих
>   вычислений.
>
> Если URL/SSL отсутствует в конфиге — останавливайся и говори пользователю
> «`<FIELD>` не настроен в `openclaw.json` — напиши админу». Хост сам не гадай.

Читай этот файл **только** когда владелец впервые подключает Jira или
Confluence (или меняет токен). Для обычной работы смотри `SKILL.md`,
туда не лезь.

Веди **по одному сервису за раз**. Если не настроены оба — начни с Jira
(пользователи в 9 из 10 случаев спрашивают именно о ней).

## Перед стартом

Прочитай конфиг, чтобы понять, какой токен пуст:

```bash
jq '.skills.entries.atlassian.env' /root/.openclaw/openclaw.json
```

Ожидаемые поля:

- `JIRA_URL`, `JIRA_SSL_VERIFY` — предустановлены, не трогать
- `JIRA_PAT_TOKEN` — заполняет пользователь (его мы и подключаем)
- `CONFLUENCE_URL`, `CONFLUENCE_SSL_VERIFY` — предустановлены, не трогать
- `CONFLUENCE_PAT_TOKEN` — заполняет пользователь

## Jira (Data Center)

### Шаг 1 — Попроси пользователя создать PAT

Сначала прочитай URL из конфига (чтобы вставить в ссылку):

```bash
JIRA_URL=$(jq -r '.skills.entries.atlassian.env.JIRA_URL // empty' /root/.openclaw/openclaw.json)
```

Отправь пользователю DM с уже подставленным URL:

> Подключаем Jira. Делаем так:
>
> 1. Открой в браузере → **$JIRA_URL/secure/ViewProfile.jspa**
> 2. Слева панель «Profile» → **Personal Access Tokens** → **Create token**
> 3. В форме:
>    • Name: `gigaclaw` (или любое понятное)
>    • Expiry: **Never** или максимум, сколько Jira даст
> 4. Жми **Create**. Выскочит длинная строка токена.
> 5. **Скопируй её сразу** (Jira покажет токен один раз) и пришли мне
>    следующим сообщением.

Жди ответ пользователя.

### Шаг 2 — Сохрани токен

Когда пользователь пришлёт токен (длинная буквенно-цифровая строка),
сохрани через config API. **Не повторяй токен в ответе**, даже частично,
даже в «подтверждающем» сообщении.

```bash
openclaw config set skills.entries.atlassian.env.JIRA_PAT_TOKEN "<значение-от-пользователя>"
```

### Шаг 3 — Sanity-check (обязательно!)

Сделай реальный запрос в Jira от лица пользователя. Если вернулись
задачи — авторизация работает. 401/403 — токен битый или без прав.

```bash
CFG=/root/.openclaw/openclaw.json
export JIRA_URL=$(jq -r '.skills.entries.atlassian.env.JIRA_URL // empty' "$CFG")
export JIRA_PAT_TOKEN=$(jq -r '.skills.entries.atlassian.env.JIRA_PAT_TOKEN // empty' "$CFG")
export JIRA_SSL_VERIFY=true

cd /root/.openclaw/workspace/skills/atlassian && python3 -c "
from scripts.jira_search import jira_search
print(jira_search(jql='assignee = currentUser() ORDER BY updated DESC', limit=3, fields='key,summary,status'))
"
```

Отчитайся перед пользователем — обязательно с **реальными ключами и
названиями задач** из ответа (не плейсхолдеры):

> ✅ Jira подключена. Вот твои последние задачи:
> • <KEY> — <summary> *(status)*
> • <KEY> — <summary> *(status)*
> • <KEY> — <summary> *(status)*

После этого **вернись к разделу «После успешного подключения» в конце
этого файла** — там описано, как перейти к следующему сервису.

### Если Шаг 3 упал

Jira Data Center через PAT авторизуется только Bearer. Если 401/403
— значит токен не тот; другие схемы (Basic Auth, username+password)
не пробуй, это не поможет. Просто попроси пересоздать:

- **401 Unauthorized** → токен не принят. Возможно, не весь скопировал
  или истёк. Пользователю: «Токен не прошёл — похоже, в строке лишний
  пробел или она обрезана. Создай новый и пришли ещё раз».
- **403 Forbidden** → токен живой, но без прав. На DC это редкий случай
  (обычно PAT работает). Попроси проверить, что токен создан от нужной
  учётки.
- **Network timeout** → VPN/сеть. Спроси пользователя, открывается ли
  Jira из его сети. Для корпоративной Jira это бывает, если бот
  крутится вне корпсети.

## Confluence

Делегируй сюда **только если пользователь согласился** подключать
Confluence. Не подключай автоматически — некоторые команды пользуются
только Jira.

### Шаг 1 — создание PAT

```bash
CONFLUENCE_URL=$(jq -r '.skills.entries.atlassian.env.CONFLUENCE_URL // empty' /root/.openclaw/openclaw.json)
```

> Confluence — процедура похожая:
>
> 1. Открой **$CONFLUENCE_URL/plugins/personalaccesstokens/usertokens.action**
> 2. **Create token** → Name: `gigaclaw`, Expiry: Never
> 3. Скопируй и пришли мне.

### Шаг 2 — сохранение

```bash
openclaw config set skills.entries.atlassian.env.CONFLUENCE_PAT_TOKEN "<значение>"
```

### Шаг 3 — sanity-check

Бьём в `/rest/api/user/current` — endpoint, который при живом токене
вернёт профиль вне зависимости от прав на конкретные пространства.
Это изолирует проверку авторизации от скоупа доступа.

```bash
CFG=/root/.openclaw/openclaw.json
CONFLUENCE_URL=$(jq -r '.skills.entries.atlassian.env.CONFLUENCE_URL // empty' "$CFG")
CONFLUENCE_PAT_TOKEN=$(jq -r '.skills.entries.atlassian.env.CONFLUENCE_PAT_TOKEN // empty' "$CFG")

curl -sf -H "Authorization: Bearer $CONFLUENCE_PAT_TOKEN" \
  "$CONFLUENCE_URL/rest/api/user/current" \
  | jq '{username, displayName, email: .email}'
```

Если вернулся JSON с `displayName` / `username` — авторизация работает.
Отчитайся пользователю с **реальным именем** из ответа:

> ✅ Confluence подключён. Вижу тебя как `<username>` (<displayName>).
> Можешь спрашивать «найди страницу про X», «покажи что нового в пространстве Y».

После этого переходи к разделу «После успешного подключения» ниже.

## После успешного подключения

Не заканчивай онбординг сам — вернись к
`/root/.openclaw/workspace/BOOT.md` Шаг 4. Там описан алгоритм: посмотри,
какие токены ещё пустые, предложи один конкретный следующий сервис
(не списком), либо отправь финальное сообщение если всё подключено.

**Не предлагай следующий сервис в том же сообщении, где отчитываешься
об успехе** — это отдельный шаг после подтверждения пользователем.

## Важно

- **Никогда не повторяй токен в ответе**, даже частично, даже «для подтверждения».
- Если пользователь прислал что-то непохожее на токен (короткое, с
  пробелами, с осмысленными словами) — попроси переприслать, не сохраняй
  мусор.
- После сохранения скилл работает уже на следующем вызове —
  autoload подхватит новый токен (см. `SKILL.md`).
  **Перезапуск шлюза не нужен.**
