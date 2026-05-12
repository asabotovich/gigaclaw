---
name: himalaya
description: "CLI to manage emails via IMAP/SMTP. Use `himalaya` to list, read, write, reply, forward, search, and organize emails from the terminal. Supports multiple accounts and message composition with MML (MIME Meta Language)."
homepage: https://github.com/pimalaya/himalaya
metadata: {"clawdbot":{"emoji":"📧","requires":{"bins":["himalaya"]},"install":[{"id":"brew","kind":"brew","formula":"himalaya","bins":["himalaya"],"label":"Install Himalaya (brew)"}]}}
---

# Himalaya Email CLI

Himalaya is a CLI email client that lets you manage emails from the terminal using IMAP, SMTP, Notmuch, or Sendmail backends.

## Prerequisites

1. Himalaya CLI installed (`himalaya --version` to verify)
2. A configuration file at `~/.config/himalaya/config.toml`
3. IMAP/SMTP credentials configured (password stored securely)

## Configuration Setup

Run the interactive wizard to set up an account:
```bash
himalaya account configure
```

Or create `~/.config/himalaya/config.toml` manually:
```toml
[accounts.personal]
email = "you@example.com"
display-name = "Your Name"
default = true

backend.type = "imap"
backend.host = "imap.example.com"
backend.port = 993
backend.encryption.type = "tls"
backend.login = "you@example.com"
backend.auth.type = "password"
backend.auth.cmd = "pass show email/imap"  # or use keyring

message.send.backend.type = "smtp"
message.send.backend.host = "smtp.example.com"
message.send.backend.port = 587
message.send.backend.encryption.type = "start-tls"
message.send.backend.login = "you@example.com"
message.send.backend.auth.type = "password"
message.send.backend.auth.cmd = "pass show email/smtp"
```

## Common Operations

### List Folders

```bash
himalaya folder list
```

### List Emails

List emails in INBOX (default):
```bash
himalaya envelope list
```

List emails in a specific folder:
```bash
himalaya envelope list --folder "Sent"
```

List with pagination:
```bash
himalaya envelope list --page 1 --page-size 20
```

### Search Emails

```bash
himalaya envelope list from john@example.com subject meeting
```

### Read an Email

Read email by ID (shows plain text):
```bash
himalaya message read 42
```

Export raw MIME:
```bash
himalaya message export 42 --full
```

### Reply / Forward / Send — non-interactive (this is the only mode that works for bots)

`himalaya message reply` and `himalaya message forward` accept the body
as a positional argument. **No `$EDITOR` involved, the message is sent
directly.** This is the path bots must use — there is no terminal to
open an editor in.

Reply:
```bash
himalaya message reply 42 "Body of the reply."
himalaya message reply 42 --all "Body."                  # reply-all
himalaya message reply 42 -H "Cc:user@example.com" "Body."
```

Forward:
```bash
himalaya message forward 42 -H "To:recipient@example.com" "Optional comment."
```

New message — pipe `template write` into `template send`:
```bash
himalaya template write \
    -H "To:recipient@example.com" \
    -H "Subject:Hello" \
    "Body." \
  | himalaya template send
```

`template write` fills `From:` from config, attaches your signature, and
emits the draft to stdout. `template send` reads the draft from stdin,
compiles it (MML → MIME, so non-ASCII subjects/bodies are encoded
correctly), delivers via SMTP, and prints `Message successfully sent!`.

**Don't use `himalaya message send -H ...` for a new message** — `send`
has no `-H` flag (only `reply`/`forward` do), and its `[MESSAGE]...`
positional argument takes an already-built raw RFC822 string, which is
easy to malform (line endings, header encoding for non-ASCII).
The `template write | template send` pipe avoids both traps.

#### Confirming the message was actually sent

A non-zero exit code means failure, but **exit 0 alone is not enough** —
several `himalaya` subcommands print drafts to stdout and exit 0 without
sending anything. The send was real **only** if stdout contains the
literal string:

```
Message successfully sent!
```

If you don't see that line, treat the operation as failed and retry —
do not tell the user "отправлено" / "переслано" prematurely.

#### Antipatterns

**Don't use `himalaya template reply` / `himalaya template forward`
when you actually want to send.** Those subcommands only render the
draft template to stdout — exit 0 + non-empty stdout is normal output,
**not delivery**. If you must use the template flow, pipe the result
into `himalaya template send` (which actually delivers and prints
`Message successfully sent!`):

```bash
himalaya template forward 42 \
  | sed '0,/^$/{s/^To: */&recipient@example.com/}' \
  | himalaya template send
```

But for ordinary cases prefer the direct `message reply` / `message
forward` form above — fewer ways to get it wrong.

**Don't try to override `From:` via `-H` or in a template.** The sender
address is taken from `~/.config/himalaya/config.toml` (`accounts.<name>.email`).
Setting `From:` to anything else is rejected by SMTP (e.g. `550 not
local sender over smtp` from mail.ru) — you can only send as the
configured account.

**Don't pipe a heredoc with `To:` into `himalaya template forward
<id>`.** The heredoc is consumed as the **body**, not as headers. The
forwarded message ends up with an empty `To:` and goes nowhere. Use
`-H "To:..."` arguments instead, as shown above.

### Interactive aliases (won't work in bot exec — for human reference only)

```bash
himalaya message reply 42        # opens $EDITOR
himalaya message forward 42      # opens $EDITOR
himalaya message write           # opens $EDITOR
```

### Move/Copy Emails

Move to folder:
```bash
himalaya message move 42 "Archive"
```

Copy to folder:
```bash
himalaya message copy 42 "Important"
```

### Delete an Email

```bash
himalaya message delete 42
```

### Manage Flags

Add flag:
```bash
himalaya flag add 42 --flag seen
```

Remove flag:
```bash
himalaya flag remove 42 --flag seen
```

## Multiple Accounts

List accounts:
```bash
himalaya account list
```

Use a specific account:
```bash
himalaya --account work envelope list
```

## Attachments

Save attachments from a message:
```bash
himalaya attachment download 42
```

Save to specific directory:
```bash
himalaya attachment download 42 --dir ~/Downloads
```

## Output Formats

Most commands support `--output` for structured output:
```bash
himalaya envelope list --output json
himalaya envelope list --output plain
```

## Debugging

Enable debug logging:
```bash
RUST_LOG=debug himalaya envelope list
```

Full trace with backtrace:
```bash
RUST_LOG=trace RUST_BACKTRACE=1 himalaya envelope list
```

## Tips

- Use `himalaya --help` or `himalaya <command> --help` for detailed usage.
- Message IDs are relative to the current folder; re-list after folder changes.
- For composing rich emails with attachments, use MML syntax (upstream docs: <https://crates.io/crates/mml-lib>).
- Store passwords securely using `pass`, system keyring, or a command that outputs the password.
