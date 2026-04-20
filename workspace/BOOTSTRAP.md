# BOOTSTRAP — first-run onboarding

You exist. Workspace is prepared. Before you start working with the user:

## Step 1 — Announce yourself

On the first DM from `${ADMIN_USERNAME}`, greet them proactively. Keep it brief.
Then run the checklist below.

## Step 2 — Check credentials

Read `/root/.openclaw/openclaw.json` (`exec` tool + `jq`) and inspect these paths:

- `.skills.entries.atlassian.env.JIRA_PAT_TOKEN`
- `.skills.entries.atlassian.env.CONFLUENCE_PAT_TOKEN`
- `.skills.entries.glab.env.GITLAB_TOKEN`
- `.skills.entries.himalaya.env.EMAIL_PASSWORD` (if himalaya is expected)

For each that is **missing or empty**, tell the user what's not configured and
offer to set it up. Give them the link to generate a token:

| Service | Link to generate PAT |
|---|---|
| Jira (Data Center) | `${JIRA_URL}/secure/ViewProfile.jspa` → Personal Access Tokens |
| Confluence | `${CONFLUENCE_URL}/plugins/personalaccesstokens/usertokens.action` |
| GitLab | `https://${GITLAB_HOST}/-/user_settings/personal_access_tokens` (scopes: `read_api`, `read_repository`) |
| Email | ask user for app-password from the provider |

## Step 3 — Save tokens when user provides them

Use `openclaw config set` via the `exec` tool. Nested paths are supported:

```
openclaw config set skills.entries.atlassian.env.JIRA_PAT_TOKEN "<token>"
openclaw config set skills.entries.atlassian.env.CONFLUENCE_PAT_TOKEN "<token>"
openclaw config set skills.entries.glab.env.GITLAB_TOKEN "<token>"
openclaw config set skills.entries.himalaya.env.EMAIL_PASSWORD "<password>"
```

After the value is set, it is **immediately available** on the next skill
invocation — no container restart needed. Do NOT echo the token back to the user.

## Step 4 — Confirm and proceed

Acknowledge what was saved in one short message (without leaking the token),
and resume normal operation.

## Step 5 — Cleanup

Once every non-optional credential is either set OR explicitly declined by the
user (e.g., "skip GitLab for now"), **delete this file**:

```
exec: rm /root/.openclaw/workspace/BOOTSTRAP.md
```

Do not bring onboarding up again unless the user asks.

---

## Notes

- **Do not block** the user with onboarding. If they send a real question before
  you finish the checklist, answer it using whatever credentials are available,
  and only surface missing ones if they're relevant to that task.
- **Do not echo secrets** in your replies, even partially.
- **Allowlist is already set** — only `${ADMIN_USERNAME}` can DM you (platform-enforced).
- If `openclaw config set` fails, fall back to `jq` + atomic write of
  `/root/.openclaw/openclaw.json`.
