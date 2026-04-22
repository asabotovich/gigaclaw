---
name: mattermost
description: "Mattermost REST API access: fetch channel message history, read thread replies, get user info, check online status, list channel members. Use when asked about channel history, thread content, user details, or who is online."
---

# Mattermost REST API

Use this skill when the user asks to:
- show recent messages / history in a channel
- read a thread (replies under a specific post)
- look up info about a user
- check if someone is online
- list who is in a channel

## Prerequisites

Token and base URL are already in the container's environment — no config
lookup needed:

```bash
MM_TOKEN="$MM_BOT_TOKEN"
MM_URL="$MM_BASE_URL"
```

Run both lines at the start of every session that uses this skill.

## Channel ID

The channel ID is available in your session context — it looks like `#de76e8ba16da8c3b98a26adb206bf8cf`.
Strip the leading `#` before using it in API calls:

```bash
CHANNEL_ID="de76e8ba16da8c3b98a26adb206bf8cf"  # paste the ID from context, without #
```

## Channel History

Fetch the last N messages (default: 30). Messages are printed oldest-first with timestamp, username, and text:

```bash
curl -sf -H "Authorization: Bearer $MM_TOKEN" \
  "$MM_URL/api/v4/channels/$CHANNEL_ID/posts?per_page=30" \
  | python3 -c "
import json, sys, datetime
data = json.load(sys.stdin)
order = data.get('order', [])
posts = data.get('posts', {})
for pid in reversed(order):
    p = posts[pid]
    ts = datetime.datetime.fromtimestamp(p.get('create_at', 0) // 1000).strftime('%Y-%m-%d %H:%M')
    print(f'{ts}  {p.get(\"props\", {}).get(\"username\", p.get(\"user_id\", \"\"))} : {p.get(\"message\", \"\")}')
"
```

To fetch more messages, increase `per_page` (max 200). To go further back, add `&before=<post_id>`.

To resolve `user_id` to a username in the output, use the user lookup below.

## Thread History

A thread in Mattermost is a chain of replies under a single root post. Use `GET /api/v4/posts/{post_id}/thread` where `post_id` is the **root post ID** of the thread.

The current thread's root post ID is available in the session context (OpenClaw sets `replyToMode: first`, so each thread has its own session). Ask the user to paste the root post URL or ID if it is not clear from context.

```bash
ROOT_POST_ID="<paste root post id here>"
curl -sf -H "Authorization: Bearer $MM_TOKEN" \
  "$MM_URL/api/v4/posts/$ROOT_POST_ID/thread" \
  | python3 -c "
import json, sys, datetime
data = json.load(sys.stdin)
order = data.get('order', [])
posts = data.get('posts', {})
for pid in order:
    p = posts[pid]
    ts = datetime.datetime.fromtimestamp(p.get('create_at', 0) // 1000).strftime('%Y-%m-%d %H:%M')
    indent = '  ↳ ' if p.get('root_id') else ''
    print(f'{ts}  {indent}{p.get(\"user_id\", \"\")} : {p.get(\"message\", \"\")}')
"
```

Notes:
- The root post itself is included in the response (no `root_id` field on it).
- Replies have `root_id` set to the root post ID.
- The response is not paginated — all replies are returned at once.
- To get the post ID from a Mattermost URL: the last segment of the permalink is the post ID.

## User Info

**By user ID:**

```bash
curl -sf -H "Authorization: Bearer $MM_TOKEN" \
  "$MM_URL/api/v4/users/$USER_ID" \
  | python3 -c "
import json, sys
u = json.load(sys.stdin)
print(f'Username : @{u[\"username\"]}')
print(f'Name     : {u.get(\"first_name\",\"\")} {u.get(\"last_name\",\"\")}')
print(f'Email    : {u.get(\"email\",\"\")}')
print(f'Nickname : {u.get(\"nickname\",\"\")}')
print(f'Roles    : {u.get(\"roles\",\"\")}')
print(f'Locale   : {u.get(\"locale\",\"\")}')
"
```

**By username** (without `@`):

```bash
curl -sf -H "Authorization: Bearer $MM_TOKEN" \
  "$MM_URL/api/v4/users/username/$USERNAME" \
  | python3 -c "
import json, sys
u = json.load(sys.stdin)
print(f'ID       : {u[\"id\"]}')
print(f'Username : @{u[\"username\"]}')
print(f'Name     : {u.get(\"first_name\",\"\")} {u.get(\"last_name\",\"\")}')
print(f'Email    : {u.get(\"email\",\"\")}')
print(f'Roles    : {u.get(\"roles\",\"\")}')
"
```

## User Online Status

```bash
curl -sf -H "Authorization: Bearer $MM_TOKEN" \
  "$MM_URL/api/v4/users/$USER_ID/status" \
  | python3 -c "
import json, sys
s = json.load(sys.stdin)
print(f'Status: {s[\"status\"]}')  # online / away / dnd / offline
"
```

## Channel Members

List all members of the current channel (paginated, 200 per page):

```bash
curl -sf -H "Authorization: Bearer $MM_TOKEN" \
  "$MM_URL/api/v4/channels/$CHANNEL_ID/members?per_page=200" \
  | python3 -c "
import json, sys
members = json.load(sys.stdin)
for m in members:
    print(m.get('user_id', ''))
"
```

To get display names for all members, look up each `user_id` with the user-by-ID command above.

## Access Control

- Channel history and member list: available to **all users** (the bot is already a member of the channel).
- User email and full profile: show only to **admins** (per TOOLS.md rules).
- Never expose one user's private data to another user.
