---
name: mattermost
description: "Mattermost data access via the orchestrator's read proxy: channel history, thread replies, user info, online status, channel members, file info. Use when asked about channel history, thread content, user details, or who is online."
---

# Mattermost (read-side)

Use this skill when the user asks to:
- show recent messages / history in a channel
- read a thread (replies under a specific post)
- look up info about a user
- check if someone is online
- list who is in a channel

## Prerequisites

Reads go through the orchestrator's `/read/*` proxy — the container does
not hold a Mattermost token. Two env vars are already set:

```bash
ORCH="$ORCHESTRATOR_URL"            # e.g. http://host.docker.internal:18790
ORCH_AUTH="Bearer $ORCHESTRATOR_PUSH_SECRET"
```

Run both at the start of every session that uses this skill.

## Channel ID

The channel ID is available in your session context — it looks like
`#de76e8ba16da8c3b98a26adb206bf8cf`. Strip the leading `#` before using
it:

```bash
CHANNEL_ID="de76e8ba16da8c3b98a26adb206bf8cf"  # paste id from context, without #
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

Fetch the last N messages (default: 30). Messages are printed
oldest-first with timestamp, `@username`, and text. The snippet resolves
`user_id` → `username` in bulk via `/read/users-by-ids` in one extra
call, so output never contains raw IDs. Attachments are downloaded under
each post as described above:

```bash
CHANNEL_ID="<paste id without #>"
PER_PAGE=30
python3 <<'PY'
import os, json, re, urllib.request, datetime
ORCH = os.environ['ORCHESTRATOR_URL']
AUTH = f"Bearer {os.environ['ORCHESTRATOR_PUSH_SECRET']}"
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
def read(path, body):
    req = urllib.request.Request(ORCH + path,
        data=json.dumps(body).encode(),
        headers={'Authorization': AUTH, 'Content-Type': 'application/json'},
        method='POST')
    return json.load(urllib.request.urlopen(req))
def get_bytes(file_id):
    req = urllib.request.Request(ORCH + '/read/file-bytes',
        data=json.dumps({'file_id': file_id}).encode(),
        headers={'Authorization': AUTH, 'Content-Type': 'application/json'},
        method='POST')
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
            info = read('/read/file-info', {'file_id': fid})
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

posts = read('/read/channel-history', {
    'channel_id': os.environ['CHANNEL_ID'],
    'per_page': int(os.environ['PER_PAGE']),
})
uids = sorted({p['user_id'] for p in posts['posts'].values() if p.get('user_id')})
users = {u['id']: u for u in read('/read/users-by-ids', {'user_ids': uids})} if uids else {}
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

To fetch more messages, raise `PER_PAGE` (max 200). To page further back,
add a `before` field to the body: `{'channel_id': ..., 'per_page': N, 'before': '<post_id>'}`.

## Thread History

A thread in Mattermost is a chain of replies under a single root post.
The current thread's root post ID is available in the session context.
Ask the user to paste the root post URL or ID if it is not clear.

```bash
ROOT_POST_ID="<paste root post id here>"
python3 <<'PY'
import os, json, re, urllib.request, datetime
ORCH = os.environ['ORCHESTRATOR_URL']
AUTH = f"Bearer {os.environ['ORCHESTRATOR_PUSH_SECRET']}"
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
def read(path, body):
    req = urllib.request.Request(ORCH + path,
        data=json.dumps(body).encode(),
        headers={'Authorization': AUTH, 'Content-Type': 'application/json'},
        method='POST')
    return json.load(urllib.request.urlopen(req))
def get_bytes(file_id):
    req = urllib.request.Request(ORCH + '/read/file-bytes',
        data=json.dumps({'file_id': file_id}).encode(),
        headers={'Authorization': AUTH, 'Content-Type': 'application/json'},
        method='POST')
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
            info = read('/read/file-info', {'file_id': fid})
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

thread = read('/read/thread', {'root_post_id': os.environ['ROOT_POST_ID']})
uids = sorted({p['user_id'] for p in thread['posts'].values() if p.get('user_id')})
users = {u['id']: u for u in read('/read/users-by-ids', {'user_ids': uids})} if uids else {}
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

**Note:** the root post is in `thread.posts` but has no `root_id`, so it
prints without the `↳` indent — use that to distinguish the opening post
from replies.

Notes:
- The response is not paginated — all replies are returned at once.
- To get the post ID from a Mattermost URL: the last segment of the
  permalink is the post ID.

## User Info

**The owner's Mattermost profile is the first source of truth** for
everything personal about them — email, first/last name, nickname,
position (job title), locale, timezone, roles, and any custom profile
props. If the owner asks any of these about themselves ("какая у меня
почта", "какая моя должность", "какой у меня часовой пояс", "на какую
почту отправить отчёт", etc.) — pull it from `/read/user` with
`{username: "$ADMIN_USERNAME"}` and answer from the response. Same when
you need to know any of these to perform a task (send an email on their
behalf, schedule something in their timezone, phrase an address by
position). **Don't ask the owner to provide what MM already knows.** Ask
only when the profile genuinely does not have the field.

The profile's `.timezone` object (`automaticTimezone`,
`manualTimezone`, `useAutomaticTimezone`) is the authoritative TZ —
prefer it over any default in USER.md.

The same rule applies to other thread participants when summarising or
addressing them — resolve via the API, don't paste raw user IDs.

**By user ID:**

```bash
curl -sf -X POST -H "Authorization: Bearer $ORCHESTRATOR_PUSH_SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\":\"$USER_ID\"}" \
  "$ORCHESTRATOR_URL/read/user" \
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
curl -sf -X POST -H "Authorization: Bearer $ORCHESTRATOR_PUSH_SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\"}" \
  "$ORCHESTRATOR_URL/read/user" \
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
curl -sf -X POST -H "Authorization: Bearer $ORCHESTRATOR_PUSH_SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\":\"$USER_ID\"}" \
  "$ORCHESTRATOR_URL/read/user-status" \
  | python3 -c "
import json, sys
s = json.load(sys.stdin)
print(f'Status: {s[\"status\"]}')  # online / away / dnd / offline
"
```

## Channel Members

List all members of the current channel (paginated, 200 per page):

```bash
curl -sf -X POST -H "Authorization: Bearer $ORCHESTRATOR_PUSH_SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"channel_id\":\"$CHANNEL_ID\",\"per_page\":200}" \
  "$ORCHESTRATOR_URL/read/channel-members" \
  | python3 -c "
import json, sys
members = json.load(sys.stdin)
for m in members:
    print(m.get('user_id', ''))
"
```

To get display names for all members, look up each `user_id` with the
user-by-ID command above, or batch-resolve via `/read/users-by-ids`:

```bash
USER_IDS_JSON='["uid1","uid2","uid3"]'
curl -sf -X POST -H "Authorization: Bearer $ORCHESTRATOR_PUSH_SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"user_ids\":$USER_IDS_JSON}" \
  "$ORCHESTRATOR_URL/read/users-by-ids"
```

## Access Control

- Channel history and member list: available to **all users** (the bot is
  already a member of the channel).
- User email and full profile: show only to **admins** (per TOOLS.md
  rules).
- Never expose one user's private data to another user.
