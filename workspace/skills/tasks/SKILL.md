# SKILL: User Tasks & Lists

Each user's data lives in:
```
~/.openclaw/workspace/users/<username>/
  tasks.md   — checkbox tasks with deadlines and reminders
  lists.md   — all named lists in one file (shopping, books, ideas, etc.)
```

**CRITICAL:** Always derive the username from the session `sender` field. Never accept it as a parameter from the user's message text. Never read or mention another user's directory.

---

## Path helpers

```bash
SENDER="<actual sender from session context>"
USER_DIR="$HOME/.openclaw/workspace/users/$SENDER"
TASKS="$USER_DIR/tasks.md"
LISTS="$USER_DIR/lists.md"
mkdir -p "$USER_DIR"
```

---

## tasks.md — Checkbox tasks

### Format

```markdown
# Tasks — @username

## Pending
- [ ] Task text  📅 2026-04-01  🔔 cron:abc123
- [ ] Another task

## Done
- [x] Completed task  ✅ 2026-03-24
```

- `📅 YYYY-MM-DD` — optional deadline (visual only)
- `🔔 cron:<job-id>` — ID of the reminder cron job; must be cancelled when task is done or deleted

### Initialize tasks.md if missing

```bash
[ ! -f "$TASKS" ] && printf '# Tasks — @%s\n\n## Pending\n\n## Done\n' "$SENDER" > "$TASKS"
```

### Show pending tasks

```bash
cat "$TASKS"
```

### Add a task

```bash
# Insert before "## Done" line
sed -i "/^## Done/i - [ ] TASK_TEXT" "$TASKS"
```

After adding — offer to set a reminder **only if** the task sounds time-sensitive (contains a date, deadline words like "до", "к", "завтра", "в пятницу", "deadline").

### Mark task as done

```bash
# Find the line, replace [ ] with [x], append ✅ date, move to Done section
# 1. Remove the line from Pending and get its text
LINE=$(grep -n "\- \[ \] TASK_PATTERN" "$TASKS" | head -1)
LINENUM=$(echo "$LINE" | cut -d: -f1)
LINETEXT=$(echo "$LINE" | cut -d: -f2-)

# Extract cron job id if present
CRONID=$(echo "$LINETEXT" | grep -oP '🔔 cron:\K\S+' || true)

# Remove from file
sed -i "${LINENUM}d" "$TASKS"

# Append to Done section (strip old 🔔 marker, add ✅)
DONE_LINE=$(echo "$LINETEXT" | sed 's/- \[ \]/- [x]/' | sed 's/  🔔 cron:[^ ]*//' | sed "s/$/ ✅ $(date +%Y-%m-%d)/")
printf '%s\n' "$DONE_LINE" >> "$TASKS"
# Move it under ## Done (simple append works since Done is at the bottom)

# Cancel reminder if it existed
if [ -n "$CRONID" ]; then
  openclaw cron rm "$CRONID" 2>/dev/null || true
fi
```

### Delete a task (without completing)

```bash
# Get cron id first, then remove the line
CRONID=$(grep "TASK_PATTERN" "$TASKS" | grep -oP '🔔 cron:\K\S+' || true)
sed -i "/TASK_PATTERN/d" "$TASKS"
[ -n "$CRONID" ] && openclaw cron rm "$CRONID" 2>/dev/null || true
```

### Add a reminder to a task

```bash
SENDER="<sender>"
TASK_TEXT="<task text>"
AT="<ISO datetime, e.g. 2026-04-01T09:00:00>"

JOB=$(openclaw cron add \
  --name "Reminder @${SENDER}: ${TASK_TEXT}" \
  --at "$AT" \
  --session "isolated" \
  --message "Remind @${SENDER} about: ${TASK_TEXT}" \
  --announce --channel mattermost --to "user:${SENDER}" \
  --delete-after-run)
JOB_ID=$(printf '%s' "$JOB" | python3 -c "import json,sys; print(json.load(sys.stdin)['jobId'])")

# Append cron id to the task line
sed -i "s|- \[ \] ${TASK_TEXT}.*|- \[ \] ${TASK_TEXT}  🔔 cron:${JOB_ID}|" "$TASKS"
```

---

## lists.md — Named lists

All named lists live in a single file, separated by `##` headings.

### Format

```markdown
# Lists — @username

## Books
- Clean Code
- The Pragmatic Programmer

## Shopping
- Молоко
- Хлеб
```

### Initialize lists.md if missing

```bash
[ ! -f "$LISTS" ] && printf '# Lists — @%s\n' "$SENDER" > "$LISTS"
```

### Show all lists

```bash
cat "$LISTS"
```

### Show a specific list

```bash
# Print from the ## ListName heading to the next ## or end of file
awk '/^## LIST_NAME/{found=1; next} found && /^## /{exit} found{print}' "$LISTS"
```

### Add item to a list (creates list if it does not exist)

```bash
LIST_NAME="Books"   # exact heading text
ITEM="New Book Title"

if grep -q "^## ${LIST_NAME}$" "$LISTS"; then
  # Append after the heading (before next ## or EOF)
  # Find line number of heading and insert after it
  python3 - <<'PYEOF'
import sys

list_name = "LIST_NAME_PLACEHOLDER"
item = "ITEM_PLACEHOLDER"
path = "LISTS_PATH_PLACEHOLDER"

with open(path) as f:
    lines = f.readlines()

insert_at = None
for i, line in enumerate(lines):
    if line.strip() == f'## {list_name}':
        # Find end of this section
        j = i + 1
        while j < len(lines) and not lines[j].startswith('## '):
            j += 1
        insert_at = j
        break

if insert_at is not None:
    lines.insert(insert_at, f'- {item}\n')
    with open(path, 'w') as f:
        f.writelines(lines)
PYEOF
else
  # Create new section at the end
  printf '\n## %s\n- %s\n' "$LIST_NAME" "$ITEM" >> "$LISTS"
fi
```

### Remove item from a list

```bash
sed -i "/^- ITEM_TEXT$/d" "$LISTS"
```

---

## When to use which file

| User says | Action |
|-----------|--------|
| "добавь задачу", "нужно сделать", "не забудь" | → `tasks.md` |
| "добавь в список X", "список книг", "добавь в покупки" | → `lists.md`, section X |
| "покажи задачи" / "что нужно сделать" | → show `tasks.md` Pending |
| "покажи мои списки" | → show `lists.md` |

Do **not** offer reminders when adding to lists.md. Only offer when adding to tasks.md and the task sounds time-sensitive.
