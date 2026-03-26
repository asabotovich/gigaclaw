#!/usr/bin/env bash
# fetch-dialogs.sh — fetch all conversations with a Mattermost user from openclaw sessions
#
# Usage:
#   ./scripts/fetch-dialogs.sh <mm_username>           # outputs JSON to stdout
#   ./scripts/fetch-dialogs.sh <mm_username> --html    # opens browser viewer
#   ./scripts/fetch-dialogs.sh --list                  # list all known users/channels
#
# Env vars (override defaults):
#   SSH_KEY   — path to SSH key (default: ~/projects/frontend_key_pair.pem)
#   SSH_HOST  — user@host       (default: root@94.139.253.10)
#   CONTAINER — container name  (default: openclaw)

set -euo pipefail

SSH_KEY="${SSH_KEY:?Set SSH_KEY env var, e.g. export SSH_KEY=~/.ssh/id_rsa}"
SSH_HOST="${SSH_HOST:?Set SSH_HOST env var, e.g. export SSH_HOST=user@hostname}"
CONTAINER="${CONTAINER:-openclaw}"
SESSIONS_DIR="/root/.openclaw/agents/main/sessions"

TARGET="${1:-}"
MODE="${2:-}"

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <mm_username|--list> [--html]" >&2
  echo "  SSH_KEY, SSH_HOST, CONTAINER env vars can override defaults" >&2
  exit 1
fi

# Run Python inside container via base64-encoded script
run_py() {
  local script="$1"
  local encoded
  encoded=$(echo "$script" | base64)
  ssh -i "$SSH_KEY" "$SSH_HOST" "echo '$encoded' | base64 -d | docker exec -i $CONTAINER python3"
}

# ── List mode ────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "--list" ]]; then
  run_py "
import json
from datetime import datetime, timezone

with open('$SESSIONS_DIR/sessions.json') as f:
    data = json.load(f)

users = {}
for key, val in data.items():
    parts = key.split(':')
    kind = name = None
    if 'direct' in parts:
        kind = 'direct'
        name = parts[parts.index('direct') + 1]
    elif 'channel' in parts:
        kind = 'channel'
        name = parts[parts.index('channel') + 1]
    if kind and name:
        ts = val.get('updatedAt', 0) if isinstance(val, dict) else 0
        k = f'{kind}:{name}'
        if k not in users or ts > users[k]:
            users[k] = ts

for k, ts in sorted(users.items(), key=lambda x: -x[1]):
    dt = datetime.fromtimestamp(ts/1000, tz=timezone.utc).strftime('%Y-%m-%d %H:%M') if ts else '?'
    print(f'{k}  (last: {dt})')
"
  exit 0
fi

# ── Fetch sessions for a user ─────────────────────────────────────────────────
JSON_OUTPUT=$(run_py "
import json, os, glob, re
from datetime import datetime, timezone

sessions_dir = '$SESSIONS_DIR'
target_user = '$TARGET'

with open(os.path.join(sessions_dir, 'sessions.json')) as f:
    sessions_map = json.load(f)

# Build sid -> context_key map from sessions.json
sid_to_ctx = {}
for k, v in sessions_map.items():
    if isinstance(v, dict) and 'sessionId' in v:
        sid = v['sessionId']
        if sid not in sid_to_ctx:
            sid_to_ctx[sid] = {'context': k, 'updatedAt': v.get('updatedAt', 0)}

def extract_sender(text):
    # 'Mattermost DM from @username:' or 'message in #ch from @username:'
    m = re.search(r'from @([\w.]+):', text)
    if m:
        return m.group(1)
    # JSON block: \"sender\": \"@username\"
    m2 = re.search(r'\"sender\":\s*\"@([\w.]+)\"', text)
    if m2:
        return m2.group(1)
    return None

def parse_session_file(fname):
    messages = []
    senders = set()
    try:
        with open(fname) as f:
            for line in f:
                try:
                    d = json.loads(line)
                    if d.get('type') != 'message':
                        continue
                    msg = d.get('message', {})
                    role = msg.get('role', '')
                    if role == 'toolResult':
                        continue
                    content = msg.get('content', '')
                    ts = d.get('timestamp', '')
                    items = content if isinstance(content, list) else [{'text': content}]
                    text_parts = []
                    tool_calls = []
                    sender = None
                    for c in items:
                        if not isinstance(c, dict):
                            continue
                        ctype = c.get('type', '')
                        if ctype == 'thinking':
                            continue
                        if ctype == 'toolCall':
                            tool_calls.append({'tool': c.get('name', ''), 'args': c.get('arguments', {})})
                            continue
                        text = c.get('text', '') or c.get('content', '')
                        if text:
                            text_parts.append(str(text))
                            if role == 'user' and sender is None:
                                sender = extract_sender(text)
                    if sender:
                        senders.add(sender)
                    if not text_parts and not tool_calls:
                        continue
                    messages.append({
                        'role': role,
                        'timestamp': ts,
                        'sender': sender,
                        'text': '\n'.join(text_parts) if text_parts else None,
                        'tool_calls': tool_calls if tool_calls else None,
                    })
                except:
                    pass
    except:
        pass
    return senders, messages

# Scan ALL session files; keep only those where target_user is an actual sender
result_sessions = []
for sid, meta in sid_to_ctx.items():
    ctx = meta['context']
    # Skip cron, subagent, and the root 'main' session
    if 'cron' in ctx or 'subagent' in ctx or ctx == 'agent:main:main':
        continue
    fname = os.path.join(sessions_dir, sid + '.jsonl')
    if not os.path.exists(fname):
        matches = glob.glob(os.path.join(sessions_dir, '*' + sid + '*.jsonl'))
        if not matches:
            continue
        fname = matches[0]
    senders, messages = parse_session_file(fname)
    if target_user not in senders:
        continue
    result_sessions.append({
        'session_id': sid,
        'context': ctx,
        'updated_at': meta['updatedAt'],
        'message_count': len(messages),
        'messages': messages,
    })

result_sessions.sort(key=lambda x: x['updated_at'])

# Also build merged timeline sorted by timestamp
all_msgs = []
for s in result_sessions:
    ctx_label = s['context'].replace('agent:main:mattermost:', '').replace('agent:main:', '')
    for m in s['messages']:
        all_msgs.append(dict(m, _ctx=ctx_label))
all_msgs.sort(key=lambda x: x.get('timestamp') or '')

result = {
    'user': target_user,
    'fetched_at': datetime.now(timezone.utc).isoformat(),
    'sessions': result_sessions,
    'merged': all_msgs,
}
print(json.dumps(result, ensure_ascii=False, indent=2))
")

# ── JSON mode ─────────────────────────────────────────────────────────────────
if [[ "$MODE" != "--html" ]]; then
  echo "$JSON_OUTPUT"
  exit 0
fi

# ── HTML viewer mode ──────────────────────────────────────────────────────────
OUTFILE="/tmp/openclaw-dialogs-${TARGET}-$(date +%s).html"

python3 - "$JSON_OUTPUT" "$TARGET" "$OUTFILE" << 'PYHTML'
import sys, json, re

raw_json, user, outfile = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.loads(raw_json)
escaped = json.dumps(data)

HTML = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenClaw · @__USER__</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0d1117;color:#c9d1d9;display:flex;height:100vh;overflow:hidden}
#sidebar{width:260px;min-width:200px;background:#161b22;border-right:1px solid #30363d;display:flex;flex-direction:column}
#sidebar-header{padding:14px 16px;border-bottom:1px solid #30363d}
#sidebar-header h1{font-size:12px;color:#8b949e;text-transform:uppercase;letter-spacing:.8px}
#sidebar-header p{font-size:12px;color:#58a6ff;margin-top:3px}
#tabs{display:flex;border-bottom:1px solid #30363d}
.tab{flex:1;padding:8px;font-size:11px;color:#8b949e;text-align:center;cursor:pointer;border-bottom:2px solid transparent}
.tab.active{color:#c9d1d9;border-bottom-color:#388bfd}
.tab:hover{color:#c9d1d9}
#session-list{overflow-y:auto;flex:1;padding:8px}
.sitem{padding:9px 12px;border-radius:6px;cursor:pointer;margin-bottom:3px;border:1px solid transparent}
.sitem:hover{background:#1f2937;border-color:#30363d}
.sitem.active{background:#1d3557;border-color:#388bfd}
.sitem-label{font-size:11px;color:#8b949e;word-break:break-all;line-height:1.3}
.sitem-meta{font-size:10px;color:#58a6ff;margin-top:3px}
#main{flex:1;display:flex;flex-direction:column;overflow:hidden}
#ctx-header{padding:10px 20px;background:#161b22;border-bottom:1px solid #30363d;font-size:11px;color:#8b949e;word-break:break-all;flex-shrink:0}
#messages{flex:1;overflow-y:auto;padding:20px}
.empty{color:#484f58;font-size:14px;text-align:center;margin-top:60px}
.msg{margin-bottom:10px;display:flex;flex-direction:column}
.msg.user{align-items:flex-end}
.msg.assistant{align-items:flex-start}
.bubble{max-width:72%;padding:9px 13px;border-radius:12px;font-size:13px;line-height:1.55;white-space:pre-wrap;word-break:break-word}
.user .bubble{background:#1d4ed8;color:#fff;border-bottom-right-radius:2px}
.assistant .bubble{background:#21262d;color:#c9d1d9;border:1px solid #30363d;border-bottom-left-radius:2px}
.tool-call{max-width:72%;background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:7px 11px;font-size:11px;color:#8b949e;font-family:monospace;margin-bottom:3px;word-break:break-all}
.tool-name{color:#f0883e;font-weight:600}
.ts{font-size:10px;color:#484f58;margin-top:3px}
.user .ts{text-align:right}
.ctx-tag{display:inline-block;font-size:9px;color:#484f58;background:#161b22;border:1px solid #30363d;border-radius:3px;padding:1px 5px;margin-bottom:3px;align-self:flex-start}
.msg.user .ctx-tag{align-self:flex-end}
</style>
</head>
<body>
<div id="sidebar">
  <div id="sidebar-header">
    <h1>Dialogs</h1>
    <p>@__USER__</p>
  </div>
  <div id="tabs">
    <div class="tab active" onclick="switchTab('sessions',this)">Sessions</div>
    <div class="tab" onclick="switchTab('merged',this)">Merged</div>
  </div>
  <div id="session-list"></div>
</div>
<div id="main">
  <div id="ctx-header">&#8592; select a session or view merged timeline</div>
  <div id="messages"><div class="empty">&#8592; Select a session</div></div>
</div>
<script>
const DATA = __DATA__;
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
function fmtTs(ts){if(!ts)return'';try{return new Date(ts).toLocaleString('ru-RU',{timeZone:'Europe/Moscow',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'})}catch(e){return''}}
function fmtCtx(ctx){return ctx.replace(/^agent:main:mattermost:/,'').replace(/^agent:main:/,'')}

let currentTab = 'sessions';
const list = document.getElementById('session-list');

function renderSidebar(){
  list.innerHTML = '';
  if(currentTab === 'merged'){
    const el = document.createElement('div');
    el.className = 'sitem';
    const total = DATA.merged.length;
    el.innerHTML = '<div class="sitem-label">All sessions merged</div><div class="sitem-meta">'+total+' messages total</div>';
    el.onclick = () => { document.querySelectorAll('.sitem').forEach(d=>d.classList.remove('active')); el.classList.add('active'); showMerged(); };
    list.appendChild(el);
    return;
  }
  [...DATA.sessions].reverse().forEach((s,ri)=>{
    const i = DATA.sessions.length-1-ri;
    const el = document.createElement('div');
    el.className = 'sitem';
    el.innerHTML = '<div class="sitem-label">'+esc(fmtCtx(s.context))+'</div><div class="sitem-meta">'+s.message_count+' msg &#183; '+fmtTs(s.updated_at)+'</div>';
    el.onclick = () => { document.querySelectorAll('.sitem').forEach(d=>d.classList.remove('active')); el.classList.add('active'); showSession(i); };
    list.appendChild(el);
  });
}

function switchTab(tab, el){
  currentTab = tab;
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
  el.classList.add('active');
  renderSidebar();
  document.getElementById('messages').innerHTML = '<div class="empty">&#8592; Select</div>';
  document.getElementById('ctx-header').textContent = tab === 'merged' ? 'Merged timeline' : 'Select a session';
}

function renderMessages(msgs, showCtx){
  const cont = document.getElementById('messages');
  cont.innerHTML = '';
  msgs.forEach(m=>{
    const isUser = m.role === 'user';
    const div = document.createElement('div');
    div.className = 'msg '+(isUser ? 'user' : 'assistant');
    let html = '';
    if(showCtx && m._ctx){
      html += '<div class="ctx-tag">'+esc(m._ctx)+'</div>';
    }
    if(m.tool_calls && m.tool_calls.length){
      m.tool_calls.forEach(tc=>{
        const args = JSON.stringify(tc.args, null, 2);
        html += '<div class="tool-call"><span class="tool-name">&#128296; '+esc(tc.tool)+'</span><br>'+esc(args.substring(0,300))+(args.length>300?'&#8230;':'')+'</div>';
      });
    }
    if(m.text){
      let txt = m.text;
      txt = txt.replace(/^System: \\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}[^\\]]*\\] Mattermost[^\\n]*\\n/, '');
      txt = txt.replace(/\\n\\nConversation info[\\s\\S]*?```[\\s\\S]*?```\\n\\nSender[\\s\\S]*?```[\\s\\S]*?```\\n/, '');
      html += '<div class="bubble">'+esc(txt.trim())+'<div class="ts">'+(isUser && m.sender ? '@'+esc(m.sender)+' &#183; ' : '')+fmtTs(m.timestamp)+'</div></div>';
    }
    div.innerHTML = html;
    cont.appendChild(div);
  });
  cont.scrollTop = cont.scrollHeight;
}

function showSession(idx){
  const s = DATA.sessions[idx];
  document.getElementById('ctx-header').textContent = fmtCtx(s.context);
  renderMessages(s.messages, false);
}

function showMerged(){
  document.getElementById('ctx-header').textContent = 'Merged timeline (' + DATA.merged.length + ' messages)';
  renderMessages(DATA.merged, true);
}

renderSidebar();
</script>
</body>
</html>"""

html = HTML.replace('__USER__', user).replace('__DATA__', escaped)
with open(outfile, 'w') as f:
    f.write(html)
PYHTML

echo "Saved: $OUTFILE" >&2
open "$OUTFILE" 2>/dev/null || xdg-open "$OUTFILE" 2>/dev/null || echo "Open manually: file://$OUTFILE"
