# GigaClaw Orchestrator Channel

Outbound channel for delivering messages from inside a GigaClaw user container
back to Mattermost. The container never connects to Mattermost directly —
the orchestrator (a separate TypeScript service on the host) holds the bot
token and routes everything through `POST /push`.

## When to use

- Cron jobs that need to send a scheduled message to the owner or into a
  channel/thread (`openclaw cron add --channel orchestrator --to <TARGET> ...`).
- BOOT.md or any other proactive send initiated by the agent (no incoming
  message to reply to).

For normal chat replies — where the agent is answering a user turn — you
do **not** pick a target. The orchestrator already knows which conversation
the turn came from and posts the agent's output there automatically.

## Target format

`<TARGET>` is a session-key-shaped string. Accepted forms (all equivalent
after the optional `agent:<id>:` prefix is stripped):

| Intent | Target |
|---|---|
| DM to a user (canonical) | `mattermost:direct:<user_id>` |
| DM to a user (legacy, bare id) | `mattermost:<user_id>` |
| Open or private channel | `mattermost:channel:<channel_id>` |
| Private group DM | `mattermost:group:<channel_id>` |
| Any of the above, inside a thread | append `:thread:<root_post_id>` |

`<user_id>`, `<channel_id>` and `<root_post_id>` are the 26-character
lowercase alphanumeric MM identifiers.

## Shortcut: the container's owner

The container runs with an `ADMIN_USER_ID` env var that holds the owner's
MM user id. Use it directly for DMs to the owner:

```bash
openclaw message --channel orchestrator \
  --to "mattermost:direct:$ADMIN_USER_ID" \
  -m "hello"
```

For thread replies to an owner DM, append `:thread:<root_post_id>` where
`<root_post_id>` is the MM id of the post that started the thread.

## What is **not** accepted

- `@username`, `user:<id>`, `channel:<name>` — the orchestrator channel
  does not resolve names or short forms. Use the full `mattermost:...`
  prefix.
- Raw usernames without `mattermost:` prefix.
- Empty strings, whitespace, unknown kind prefixes.

Failed sends surface an error to the agent — if the target shape is
wrong the tool returns `target must start with "mattermost:"...`. Fix the
target and retry; don't try a different format.
