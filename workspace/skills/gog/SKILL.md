---
name: gog
description: Google Workspace CLI for Gmail, Calendar, Drive, Contacts, Sheets, Docs, Tasks, Slides, Forms and more.
homepage: https://gogcli.sh
metadata:
  {
    "openclaw":
      {
        "emoji": "🎮",
        "requires": { "bins": ["gog"] },
        "install":
          [
            {
              "id": "brew",
              "kind": "brew",
              "formula": "steipete/tap/gogcli",
              "bins": ["gog"],
              "label": "Install gog (brew)",
            },
          ],
      },
  }
---

# gog

Use `gog` for all Google Workspace operations: Gmail, Calendar, Drive, Docs, Sheets, Tasks, Contacts.
Version: v0.12.0. Requires OAuth setup.

## Setup (once)

```bash
gog auth credentials /path/to/client_secret.json
gog auth add you@gmail.com --services gmail,calendar,drive,contacts,docs,sheets
gog auth list
```

Set `GOG_ACCOUNT=you@gmail.com` to avoid repeating `--account` on every command.

---

## Gmail

```bash
# Search threads (one row per thread)
gog gmail search 'newer_than:7d' --max 10
gog gmail search 'from:boss@company.com is:unread'

# Search individual messages (not threads)
gog gmail messages search "in:inbox from:ryanair.com" --max 20

# Read a message
gog gmail get <messageId>

# Send plain text
gog gmail send --to a@b.com --subject "Hi" --body "Hello"

# Send multi-line (heredoc)
gog gmail send --to a@b.com --subject "Hi" --body-file - <<'EOF'
Hi Name,

Thanks for meeting. Next steps:
- Item one
- Item two

Best,
Bot
EOF

# Send HTML
gog gmail send --to a@b.com --subject "Hi" --body-html "<p>Hello</p>"

# Reply to a message
gog gmail send --to a@b.com --subject "Re: Hi" --body "Reply" --reply-to-message-id <msgId>

# Create draft
gog gmail drafts create --to a@b.com --subject "Hi" --body-file ./message.txt

# Send draft
gog gmail drafts send <draftId>

# Archive / trash / mark-read
gog gmail archive <messageId>
gog gmail trash <messageId>
gog gmail mark-read <messageId>
gog gmail unread <messageId>
```

**Email formatting notes:**
- Prefer plain text. Use `--body-file` or `--body-file -` (stdin) for multi-paragraph messages.
- `--body` does not unescape `\n` — use heredoc for newlines.
- HTML: `<p>`, `<br>`, `<strong>`, `<em>`, `<a href="...">`, `<ul>/<li>`.
- Always confirm before sending.

---

## Google Docs

Full read/write support in v0.12.0.

```bash
# Read document as plain text
gog docs cat <docId>

# Show document structure (numbered paragraphs)
gog docs structure <docId>

# Export to file (formats: txt, md, pdf, docx)
gog docs export <docId> --format md --out /tmp/doc.md

# Get metadata
gog docs info <docId>

# Create new document
gog docs create "My Document Title"

# Copy document
gog docs copy <docId> "New Title"

# Write (replace all content)
gog docs write <docId> --body "New content here"
gog docs write <docId> --body-file /tmp/content.md

# Clear all content
gog docs clear <docId>

# Find and replace text
gog docs find-replace <docId> "old text" "new text"
gog docs find-replace <docId> "old text" "new text" --first   # only first occurrence

# Edit (alias for find-replace)
gog docs edit <docId> "find this" "replace with this"

# Regex replace (sed-style)
gog docs sed <docId> 's/pattern/replacement/g'

# Insert text at specific position (index)
gog docs insert <docId> "text to insert" --index 42

# Delete text range
gog docs delete --start 10 --end 50 <docId>

# List tabs
gog docs list-tabs <docId>

# Comments
gog docs comments <docId>
```

---

## Google Sheets

```bash
# Read a range
gog sheets get <sheetId> "Sheet1!A1:D10"
gog sheets get <sheetId> "Sheet1!A1:D10" --json

# Update cells
gog sheets update <sheetId> "Sheet1!A1:B2" --values-json '[["A","B"],["1","2"]]' --input USER_ENTERED

# Append rows
gog sheets append <sheetId> "Sheet1!A:C" --values-json '[["x","y","z"]]' --insert INSERT_ROWS

# Clear a range
gog sheets clear <sheetId> "Sheet1!A2:Z"

# Metadata (list tabs, dimensions)
gog sheets metadata <sheetId> --json

# Create new spreadsheet
gog sheets create "My Spreadsheet"

# Copy spreadsheet
gog sheets copy <sheetId> "New Title"

# Tab management
gog sheets add-tab <sheetId> "New Tab"
gog sheets rename-tab <sheetId> "Old Name" "New Name"
gog sheets delete-tab <sheetId> "Tab Name"

# Find and replace across sheet
gog sheets find-replace <sheetId> "old" "new"

# Formatting
gog sheets format <sheetId> "Sheet1!A1:D1" --bold
gog sheets freeze <sheetId> --rows 1
gog sheets resize-columns <sheetId> "A:D" --width 150

# Export
gog sheets export <sheetId> --format xlsx --out /tmp/sheet.xlsx
```

---

## Google Calendar

```bash
# List events
gog calendar events primary --from 2026-01-01T00:00:00Z --to 2026-01-31T23:59:59Z

# Search events
gog calendar search "standup" --from 2026-01-01T00:00:00Z

# Create event
gog calendar create primary --summary "Meeting" --from 2026-01-15T10:00:00+03:00 --to 2026-01-15T11:00:00+03:00

# Create with color
gog calendar create primary --summary "Focus" --from <iso> --to <iso> --event-color 9

# Update event
gog calendar update primary <eventId> --summary "New Title" --event-color 4

# Delete event
gog calendar delete primary <eventId>

# RSVP to invitation
gog calendar respond primary <eventId> --status accepted

# Check free/busy
gog calendar freebusy --from 2026-01-15T09:00:00Z --to 2026-01-15T18:00:00Z

# Team calendar (whole group)
gog calendar team team@company.com --from <iso> --to <iso>

# Find conflicts
gog calendar conflicts --from <iso> --to <iso>

# Special blocks
gog calendar focus-time primary --from <iso> --to <iso>
gog calendar out-of-office primary --from <iso> --to <iso>

# Available colors (IDs 1–11)
gog calendar colors
# 1:#a4bdfc 2:#7ae7bf 3:#dbadff 4:#ff887c 5:#fbd75b
# 6:#ffb878 7:#46d6db 8:#e1e1e1 9:#5484ed 10:#51b749 11:#dc2127
```

---

## Google Drive

```bash
# List files (root by default)
gog drive ls
gog drive ls --folder <folderId>

# Search
gog drive search "budget 2026"

# Get metadata
gog drive get <fileId>

# Download
gog drive download <fileId> --out /tmp/file.pdf

# Upload
gog drive upload /local/path/file.pdf --folder <folderId>

# Create folder
gog drive mkdir "Reports 2026"

# Copy / rename / move
gog drive copy <fileId> "New Name"
gog drive rename <fileId> "New Name"
gog drive move <fileId> --folder <targetFolderId>

# Delete (trash)
gog drive delete <fileId>
gog drive delete <fileId> --permanent

# Share
gog drive share <fileId> --email user@example.com --role writer
gog drive permissions <fileId>

# Print web URL
gog drive url <fileId>
```

---

## Google Tasks

```bash
# List task lists
gog tasks lists list

# List tasks in a list
gog tasks list <tasklistId>

# Add task
gog tasks add <tasklistId> --title "Do something" --due 2026-01-20T00:00:00Z

# Mark done / undo
gog tasks done <tasklistId> <taskId>
gog tasks undo <tasklistId> <taskId>

# Update task
gog tasks update <tasklistId> <taskId> --title "Updated title"

# Delete task
gog tasks delete <tasklistId> <taskId>
```

---

## Google Contacts

```bash
gog contacts list --max 20
gog contacts list --max 20 --json
```

---

## Useful flags (all commands)

| Flag | Description |
|---|---|
| `--json` / `-j` | JSON output (best for scripting) |
| `--plain` / `-p` | TSV output (stable, parseable) |
| `--dry-run` / `-n` | Print intended action, don't execute |
| `--force` / `-y` | Skip confirmations |
| `--no-input` | Never prompt; fail instead (CI-safe) |
| `--account` / `-a` | Override `GOG_ACCOUNT` per-command |

---

## Notes

- `GOG_ACCOUNT` env var sets default account; use `--account` to override per-command.
- Use `--json` + `--no-input` for scripting and automation.
- For Sheets, pass values via `--values-json` (recommended over inline rows).
- Always confirm before sending emails or creating calendar events.
- `gog gmail search` returns threads; use `gog gmail messages search` for individual emails.
- Drive file IDs can be extracted from Google URLs: `https://docs.google.com/document/d/<docId>/edit`.
