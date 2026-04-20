---
name: glab
description: Interact with GitLab using the `glab` CLI. Use when Claude needs to work with GitLab merge requests, CI/CD pipelines, issues, releases, or make API requests. Supports gitlab.com and self-hosted instances.
---

# GitLab Skill

Use the `glab` CLI to interact with GitLab. Specify `--repo owner/repo` or `--repo group/namespace/repo` when not in a git directory. Also accepts full URLs.

## Credentials (read this FIRST)

**Single source of truth: `/root/.openclaw/openclaw.json`** under `skills.entries.glab.env.*`.

**Always read credentials from the config at the start of each exec call** — do
not rely on them being in `process.env`. OpenClaw's `env` injection only happens
at gateway startup, so tokens saved mid-session require the read-each-call
pattern below (or a container restart).

Expected paths in `openclaw.json`:
- `skills.entries.glab.env.GITLAB_HOST`
- `skills.entries.glab.env.GITLAB_TOKEN` (PAT with `read_api`, `read_repository` scopes)

### Boilerplate for every call

```bash
CFG=/root/.openclaw/openclaw.json
export GITLAB_HOST=$(jq -r '.skills.entries.glab.env.GITLAB_HOST // empty' "$CFG")
export GITLAB_TOKEN=$(jq -r '.skills.entries.glab.env.GITLAB_TOKEN // empty' "$CFG")

glab mr list --repo group/project
```

Each `exec` tool call starts a fresh shell → fresh env from config → always uses current token. **No gateway restart needed.**

### If a token is missing

Ask the user for a GitLab PAT (scopes: `read_api`, `read_repository`) and save:

```bash
openclaw config set skills.entries.glab.env.GITLAB_TOKEN "<token>"
```

After save — immediately re-read and re-export using the boilerplate above; the very next call works.

**Never echo the token back to the user.**

## Setup walkthrough (use when user asks "настрой GitLab" / "подключи git")

Если `GITLAB_TOKEN` пустой — веди пользователя пошагово:

Возьми URL из конфига:
```bash
GITLAB_HOST=$(jq -r '.skills.entries.glab.env.GITLAB_HOST // empty' /root/.openclaw/openclaw.json)
```

Скажи в DM (подставив `$GITLAB_HOST`):

> Открой **https://$GITLAB_HOST/-/user_settings/personal_access_tokens**
> (войди если попросит).
>
> Создай новый токен:
> • **Token name:** `gigaclaw`
> • **Expiration date:** ставь максимум (обычно 1 год)
> • **Scopes:** обязательно `read_api`, `read_repository`
>   (если хочешь, чтобы бот мог ещё править MR — добавь `api` и `write_repository`,
>   это опционально; для старта хватит read)
> • Нажми **Create personal access token**
>
> Скопируй токен **сразу** (GitLab показывает его один раз) и пришли мне.

Когда пользователь прислал — сохрани:
```bash
openclaw config set skills.entries.glab.env.GITLAB_TOKEN "<токен>"
```

Sanity-check (используя boilerplate выше):
```bash
CFG=/root/.openclaw/openclaw.json
export GITLAB_HOST=$(jq -r '.skills.entries.glab.env.GITLAB_HOST // empty' "$CFG")
export GITLAB_TOKEN=$(jq -r '.skills.entries.glab.env.GITLAB_TOKEN // empty' "$CFG")

glab auth status          # должно показать "Logged in to ..."
glab api user             # должно показать твой профиль
```

Ответь:
> ✅ GitLab подключён. Ты — `<username>`. Готов искать MR, issues, читать файлы.

Link to generate: `https://<GITLAB_HOST>/-/user_settings/personal_access_tokens`.

## Merge Requests

List open merge requests:

```bash
glab mr list --repo owner/repo
```

View MR details:

```bash
glab mr view 55 --repo owner/repo
```

Create an MR from current branch:

```bash
glab mr create --fill --target-branch main
```

Approve, merge, or check out:

```bash
glab mr approve 55
glab mr merge 55
glab mr checkout 55
```

View MR diff:

```bash
glab mr diff 55
```

## CI/CD Pipelines

Check pipeline status for current branch:

```bash
glab ci status
```

View pipeline interactively (navigate jobs, view logs):

```bash
glab ci view
```

List recent pipelines:

```bash
glab ci list --repo owner/repo
```

Trace job logs in real time:

```bash
glab ci trace
glab ci trace 224356863  # specific job ID
glab ci trace lint       # by job name
```

Retry a failed pipeline:

```bash
glab ci retry
```

Validate `.gitlab-ci.yml`:

```bash
glab ci lint
```

## Issues

List and view issues:

```bash
glab issue list --repo owner/repo
glab issue view 42
```

Create an issue:

```bash
glab issue create --title "Bug report" --label bug
```

Add a comment:

```bash
glab issue note 42 -m "This is fixed in !55"
```

## API for Advanced Queries

Use `glab api` for endpoints not covered by subcommands. Supports REST and GraphQL.

Get project releases:

```bash
glab api projects/:fullpath/releases
```

Get MR with specific fields (pipe to jq):

```bash
glab api projects/owner/repo/merge_requests/55 | jq '.title, .state, .author.username'
```

Paginate through all issues:

```bash
glab api issues --paginate
```

GraphQL query:

```bash
glab api graphql -f query='
  query {
    currentUser { username }
  }
'
```

## JSON Output

Pipe to `jq` for filtering:

```bash
glab mr list --repo owner/repo | jq -r '.[] | "\(.iid): \(.title)"'
```

## Variables and Releases

Manage CI/CD variables:

```bash
glab variable list
glab variable set MY_VAR "value"
glab variable get MY_VAR
```

Create a release:

```bash
glab release create v1.0.0 --notes "Release notes here"
```

## Key Differences from GitHub CLI

| Concept                   | GitHub (`gh`) | GitLab (`glab`)                        |
| ------------------------- | ------------- | -------------------------------------- |
| Pull/Merge Request        | `gh pr`       | `glab mr`                              |
| CI runs                   | `gh run`      | `glab ci`                              |
| Repo path format          | `owner/repo`  | `owner/repo` or `group/namespace/repo` |
| Interactive pipeline view | N/A           | `glab ci view`                         |
