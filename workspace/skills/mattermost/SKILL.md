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

Fetch the last N messages (default: 30). Messages are printed oldest-first with timestamp, `@username`, and text. The snippet resolves `user_id` → `username` in bulk via `POST /users/ids` in one extra call, so output never contains raw IDs:

```bash
CHANNEL_ID="<paste id without #>"
PER_PAGE=30
python3 <<'PY'
import os, json, urllib.request, datetime
MM_URL, TOK = os.environ['MM_BASE_URL'], os.environ['MM_BOT_TOKEN']
def api(method, path, body=None):
    req = urllib.request.Request(MM_URL + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization': f'Bearer {TOK}', 'Content-Type': 'application/json'},
        method=method)
    return json.load(urllib.request.urlopen(req))
posts = api('GET', f'/api/v4/channels/{os.environ["CHANNEL_ID"]}/posts?per_page={os.environ["PER_PAGE"]}')
uids = sorted({p['user_id'] for p in posts['posts'].values() if p.get('user_id')})
users = {u['id']: u for u in api('POST', '/api/v4/users/ids', uids)} if uids else {}
for pid in reversed(posts.get('order', [])):
    p = posts['posts'][pid]
    u = users.get(p.get('user_id'), {})
    name = u.get('username') or p.get('user_id') or '?'
    ts = datetime.datetime.fromtimestamp(p.get('create_at', 0) // 1000).strftime('%Y-%m-%d %H:%M')
    print(f'{ts}  @{name}: {p.get("message", "")}')
PY
```

To fetch more messages, raise `PER_PAGE` (max 200). To page further back, add `&before=<post_id>` to the URL.

## Thread History

A thread in Mattermost is a chain of replies under a single root post. Use `GET /api/v4/posts/{post_id}/thread` where `post_id` is the **root post ID** of the thread.

The current thread's root post ID is available in the session context (OpenClaw sets `replyToMode: first`, so each thread has its own session). Ask the user to paste the root post URL or ID if it is not clear from context.

```bash
ROOT_POST_ID="<paste root post id here>"
python3 <<'PY'
import os, json, urllib.request, datetime
MM_URL, TOK = os.environ['MM_BASE_URL'], os.environ['MM_BOT_TOKEN']
def api(method, path, body=None):
    req = urllib.request.Request(MM_URL + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization': f'Bearer {TOK}', 'Content-Type': 'application/json'},
        method=method)
    return json.load(urllib.request.urlopen(req))
thread = api('GET', f'/api/v4/posts/{os.environ["ROOT_POST_ID"]}/thread')
uids = sorted({p['user_id'] for p in thread['posts'].values() if p.get('user_id')})
users = {u['id']: u for u in api('POST', '/api/v4/users/ids', uids)} if uids else {}
for pid in thread.get('order', []):
    p = thread['posts'][pid]
    u = users.get(p.get('user_id'), {})
    name = u.get('username') or p.get('user_id') or '?'
    ts = datetime.datetime.fromtimestamp(p.get('create_at', 0) // 1000).strftime('%Y-%m-%d %H:%M')
    indent = '  ↳ ' if p.get('root_id') else ''
    print(f'{ts}  {indent}@{name}: {p.get("message", "")}')
PY
```

**Note:** the root post is in `thread.posts` but has no `root_id`, so it prints without the `↳` indent — use that to distinguish the opening post from replies.

Notes:
- The response is not paginated — all replies are returned at once.
- To get the post ID from a Mattermost URL: the last segment of the permalink is the post ID.

## User Info

**The owner's own Mattermost profile is the first source of truth** for their
email / full name / nickname. If the owner asks "какая у меня почта?",
"который час в моём городе", "на какую почту отправить отчёт" — look up
their profile via `GET /users/username/$ADMIN_USERNAME` and use
`email`, `first_name`, `last_name`, `locale`, `nickname` from the response.
Don't ask the owner to provide what MM already knows.

The same rule applies to other thread participants when summarising or
addressing them — resolve via the API, don't paste raw user IDs.

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
