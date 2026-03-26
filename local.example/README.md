# local/ — Приватные дополнения к промтам

Эта папка показывает, как добавлять локальные инструкции боту, **не коммитя их в репозиторий**.

## Как это работает

Создай папку `local/` рядом с этой `local.example/`.
`local/` добавлена в `.gitignore` — её содержимое никогда не попадёт в git.

При запуске `./install.sh` файлы из `local/` **дописываются** в конец
соответствующего собранного файла перед копированием в контейнер:

| Файл в `local/`        | Дописывается в     |
|------------------------|--------------------|
| `agents.append.md`     | `build/AGENTS.md`  |
| `tools.append.md`      | `build/TOOLS.md`   |
| `user.append.md`       | `build/USER.md`    |

## Первоначальная настройка

```bash
cp -r local.example/ local/
# Редактируй файлы внутри local/ как угодно
```

## Пример: agents.append.md

```markdown
## Приватные инструкции

- Всегда отвечай на русском
- Обращайся к пользователю по имени
```

## Пример: tools.append.md

```markdown
## Внутренние сервисы

- Jira: https://jira.example.com (проект KEY)
- Confluence: https://confluence.example.com
- Staging: ssh root@10.0.0.5
```

## Приватные скиллы

Помимо дозаписи в существующие файлы, можно добавлять **полностью приватные скиллы**,
которые не попадут в репозиторий:

```
local/
  skills/
    my-skill/
      SKILL.md          ← инструкции для агента
      my-script.py      ← вспомогательные файлы скилла
      .skill-persist/   ← файлы которые должны пережить редеплой
        state.json      ← начальное состояние (например {})
```

При запуске `./install.sh`:
- Файлы скилла (кроме `.skill-persist/`) копируются в контейнер и обновляются при каждом редеплое
- Файлы из `.skill-persist/` копируются в `data/store/<skill>/` **один раз** (если там ещё нет)
- Автоматически генерируется `docker-compose.override.yml` с bind mount'ами

Итог — агент читает и пишет файл по обычному пути (`~/.openclaw/workspace/skills/my-skill/state.json`),
а физически он хранится на диске сервера в `data/store/my-skill/state.json` и переживает любой редеплой.

Пример сгенерированного `docker-compose.override.yml` при двух скиллах с `.skill-persist`:

```yaml
services:
  openclaw:
    volumes:
      - ./data/store/cloudsec/issues.json:/root/.openclaw/workspace/skills/cloudsec/issues.json
      - ./data/store/my-skill/state.json:/root/.openclaw/workspace/skills/my-skill/state.json
```

## Подробнее

Общая документация по развёртыванию, шаблонам и конфигурации — в [README.md](../README.md).

## Примечания

- Дозапись происходит уже после рендеринга шаблонов, поэтому `{{PLACEHOLDER}}`
  переменные в файлах `local/` **не подставляются**. Используй plain text.
- Файлы дописываются как есть, с отступом-пустой строкой.
- Если файл отсутствует — он молча игнорируется.
