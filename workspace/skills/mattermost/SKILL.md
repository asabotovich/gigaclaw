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

## Attachments in history

The history snippets below download every attachment (images and files
alike) referenced by `file_ids` on each post into
`/root/.openclaw/media/inbound/<post_id>_<file_id><ext>` — the same
allowed media root the live inbound pipeline uses. Each saved
attachment prints under its post as a marker line:

```
[attached image: /root/.openclaw/media/inbound/<file> (<mime>) name="..."]
[attached file:  /root/.openclaw/media/inbound/<file> (<mime>) name="..."]
[attachment skipped: name="..." (<mime>) size=NB reason=too_large|fetch_failed|fetch_cap]
```

What to do per marker:
- **`attached image`** → feed the path into the `image` tool (vision) for
  description; include those descriptions when summarising the
  thread/channel so the user gets what was on the screenshot.
- **`attached file`** → pick the right tool by mime: `Read` for
  text/csv/json/md, `pdftotext` (if installed) for PDF, the
  media-understanding API for audio/video. Do not pretend you read it
  if no skill is available — say so explicitly.
- **`attachment skipped`** → mention in the reply that the attachment
  existed but was unreachable for the listed reason.

Caps used by the snippets:
- per file: 10 MB (history can be heavy; oversize files are skipped)
- per fetch: 15 attachments total across all posts

## Channel History

Fetch the last N messages (default: 30). Messages are printed oldest-first with timestamp, `@username`, and text. The snippet resolves `user_id` → `username` in bulk via `POST /users/ids` in one extra call, so output never contains raw IDs. Attachments are downloaded under each post as described above:

```bash
CHANNEL_ID="<paste id without #>"
PER_PAGE=30
python3 <<'PY'
import os, json, re, urllib.request, datetime
MM_URL, TOK = os.environ['MM_BASE_URL'], os.environ['MM_BOT_TOKEN']
MEDIA_DIR = '/root/.openclaw/media/inbound'
MAX_FILE_BYTES = 10 * 1024 * 1024
MAX_ATTACHMENTS_TOTAL = 15
EXT_BY_MIME = {
    'image/jpeg':'.jpg','image/png':'.png','image/gif':'.gif','image/webp':'.webp',
    'image/heic':'.heic','image/heif':'.heif','image/svg+xml':'.svg',
    'application/pdf':'.pdf','application/json':'.json','text/plain':'.txt','text/csv':'.csv',
    'audio/mpeg':'.mp3','audio/wav':'.wav','audio/x-m4a':'.m4a',
    'video/mp4':'.mp4','video/quicktime':'.mov',
}
def api(method, path, body=None):
    req = urllib.request.Request(MM_URL + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization': f'Bearer {TOK}', 'Content-Type': 'application/json'},
        method=method)
    return json.load(urllib.request.urlopen(req))
def get_bytes(file_id):
    req = urllib.request.Request(MM_URL + f'/api/v4/files/{file_id}',
        headers={'Authorization': f'Bearer {TOK}'})
    return urllib.request.urlopen(req).read()
def ext_for(mime, hint, name):
    if hint:
        h = hint if hint.startswith('.') else '.' + hint
        if 1 < len(h) <= 8: return h
    if mime in EXT_BY_MIME: return EXT_BY_MIME[mime]
    if name and '.' in name:
        e = os.path.splitext(name)[1]
        if e: return e
    tail = mime.split('/')[-1] if '/' in mime else mime
    tail = re.sub(r'[^a-z0-9]', '', tail) or 'bin'
    return '.' + tail
def fetch_attachments(post, counter):
    fids = post.get('file_ids') or []
    if not fids: return []
    os.makedirs(MEDIA_DIR, exist_ok=True)
    lines = []
    for fid in fids:
        if counter[0] >= MAX_ATTACHMENTS_TOTAL:
            lines.append(f'    [attachment skipped: id={fid} reason=fetch_cap]')
            continue
        try:
            info = api('GET', f'/api/v4/files/{fid}/info')
            mime = info.get('mime_type','') or ''
            name = info.get('name','') or fid
            size = info.get('size', 0) or 0
            if size > MAX_FILE_BYTES:
                lines.append(f'    [attachment skipped: name={json.dumps(name)} ({mime}) size={size}B reason=too_large]')
                continue
            data = get_bytes(fid)
            if len(data) > MAX_FILE_BYTES:
                lines.append(f'    [attachment skipped: name={json.dumps(name)} ({mime}) size={len(data)}B reason=too_large]')
                continue
            ext = ext_for(mime, info.get('extension',''), name)
            fname = f'{post["id"]}_{fid}{ext}'
            path = os.path.join(MEDIA_DIR, fname)
            with open(path, 'wb') as f: f.write(data)
            os.chmod(path, 0o600)
            kind = 'attached image' if mime.startswith('image/') else 'attached file'
            lines.append(f'    [{kind}: {path} ({mime}) name={json.dumps(name)}]')
            counter[0] += 1
        except Exception as e:
            lines.append(f'    [attachment skipped: id={fid} reason=fetch_failed ({type(e).__name__})]')
    return lines

posts = api('GET', f'/api/v4/channels/{os.environ["CHANNEL_ID"]}/posts?per_page={os.environ["PER_PAGE"]}')
uids = sorted({p['user_id'] for p in posts['posts'].values() if p.get('user_id')})
users = {u['id']: u for u in api('POST', '/api/v4/users/ids', uids)} if uids else {}
counter = [0]
for pid in reversed(posts.get('order', [])):
    p = posts['posts'][pid]
    u = users.get(p.get('user_id'), {})
    name = u.get('username') or p.get('user_id') or '?'
    ts = datetime.datetime.fromtimestamp(p.get('create_at', 0) // 1000).strftime('%Y-%m-%d %H:%M')
    print(f'{ts}  @{name}: {p.get("message", "")}')
    for line in fetch_attachments(p, counter):
        print(line)
PY
```

To fetch more messages, raise `PER_PAGE` (max 200). To page further back, add `&before=<post_id>` to the URL.

## Thread History

A thread in Mattermost is a chain of replies under a single root post. Use `GET /api/v4/posts/{post_id}/thread` where `post_id` is the **root post ID** of the thread.

The current thread's root post ID is available in the session context (OpenClaw sets `replyToMode: first`, so each thread has its own session). Ask the user to paste the root post URL or ID if it is not clear from context.

```bash
ROOT_POST_ID="<paste root post id here>"
python3 <<'PY'
import os, json, re, urllib.request, datetime
MM_URL, TOK = os.environ['MM_BASE_URL'], os.environ['MM_BOT_TOKEN']
MEDIA_DIR = '/root/.openclaw/media/inbound'
MAX_FILE_BYTES = 10 * 1024 * 1024
MAX_ATTACHMENTS_TOTAL = 15
EXT_BY_MIME = {
    'image/jpeg':'.jpg','image/png':'.png','image/gif':'.gif','image/webp':'.webp',
    'image/heic':'.heic','image/heif':'.heif','image/svg+xml':'.svg',
    'application/pdf':'.pdf','application/json':'.json','text/plain':'.txt','text/csv':'.csv',
    'audio/mpeg':'.mp3','audio/wav':'.wav','audio/x-m4a':'.m4a',
    'video/mp4':'.mp4','video/quicktime':'.mov',
}
def api(method, path, body=None):
    req = urllib.request.Request(MM_URL + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization': f'Bearer {TOK}', 'Content-Type': 'application/json'},
        method=method)
    return json.load(urllib.request.urlopen(req))
def get_bytes(file_id):
    req = urllib.request.Request(MM_URL + f'/api/v4/files/{file_id}',
        headers={'Authorization': f'Bearer {TOK}'})
    return urllib.request.urlopen(req).read()
def ext_for(mime, hint, name):
    if hint:
        h = hint if hint.startswith('.') else '.' + hint
        if 1 < len(h) <= 8: return h
    if mime in EXT_BY_MIME: return EXT_BY_MIME[mime]
    if name and '.' in name:
        e = os.path.splitext(name)[1]
        if e: return e
    tail = mime.split('/')[-1] if '/' in mime else mime
    tail = re.sub(r'[^a-z0-9]', '', tail) or 'bin'
    return '.' + tail
def fetch_attachments(post, counter):
    fids = post.get('file_ids') or []
    if not fids: return []
    os.makedirs(MEDIA_DIR, exist_ok=True)
    lines = []
    for fid in fids:
        if counter[0] >= MAX_ATTACHMENTS_TOTAL:
            lines.append(f'    [attachment skipped: id={fid} reason=fetch_cap]')
            continue
        try:
            info = api('GET', f'/api/v4/files/{fid}/info')
            mime = info.get('mime_type','') or ''
            name = info.get('name','') or fid
            size = info.get('size', 0) or 0
            if size > MAX_FILE_BYTES:
                lines.append(f'    [attachment skipped: name={json.dumps(name)} ({mime}) size={size}B reason=too_large]')
                continue
            data = get_bytes(fid)
            if len(data) > MAX_FILE_BYTES:
                lines.append(f'    [attachment skipped: name={json.dumps(name)} ({mime}) size={len(data)}B reason=too_large]')
                continue
            ext = ext_for(mime, info.get('extension',''), name)
            fname = f'{post["id"]}_{fid}{ext}'
            path = os.path.join(MEDIA_DIR, fname)
            with open(path, 'wb') as f: f.write(data)
            os.chmod(path, 0o600)
            kind = 'attached image' if mime.startswith('image/') else 'attached file'
            lines.append(f'    [{kind}: {path} ({mime}) name={json.dumps(name)}]')
            counter[0] += 1
        except Exception as e:
            lines.append(f'    [attachment skipped: id={fid} reason=fetch_failed ({type(e).__name__})]')
    return lines

thread = api('GET', f'/api/v4/posts/{os.environ["ROOT_POST_ID"]}/thread')
uids = sorted({p['user_id'] for p in thread['posts'].values() if p.get('user_id')})
users = {u['id']: u for u in api('POST', '/api/v4/users/ids', uids)} if uids else {}
counter = [0]
for pid in thread.get('order', []):
    p = thread['posts'][pid]
    u = users.get(p.get('user_id'), {})
    name = u.get('username') or p.get('user_id') or '?'
    ts = datetime.datetime.fromtimestamp(p.get('create_at', 0) // 1000).strftime('%Y-%m-%d %H:%M')
    indent = '  ↳ ' if p.get('root_id') else ''
    print(f'{ts}  {indent}@{name}: {p.get("message", "")}')
    for line in fetch_attachments(p, counter):
        print(line)
PY
```

**Note:** the root post is in `thread.posts` but has no `root_id`, so it prints without the `↳` indent — use that to distinguish the opening post from replies.

Notes:
- The response is not paginated — all replies are returned at once.
- To get the post ID from a Mattermost URL: the last segment of the permalink is the post ID.

## User Info

**The owner's Mattermost profile is the first source of truth** for
everything personal about them — email, first/last name, nickname,
position (job title), locale, timezone, roles, and any custom profile
props. If the owner asks any of these about themselves ("какая у меня
почта", "какая моя должность", "какой у меня часовой пояс", "на какую
почту отправить отчёт", etc.) — pull it from
`GET /users/username/$ADMIN_USERNAME` and answer from the response.
Same when you need to know any of these to perform a task (send an
email on their behalf, schedule something in their timezone, phrase an
address by position). **Don't ask the owner to provide what MM
already knows.** Ask only when the profile genuinely does not have
the field (e.g. a preference they never set in their MM profile).

The profile's `.timezone` object (`automaticTimezone`,
`manualTimezone`, `useAutomaticTimezone`) is the authoritative TZ —
prefer it over any default in USER.md.

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
