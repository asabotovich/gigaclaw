---
name: glab
description: Interact with GitLab using the `glab` CLI. Use when Claude needs to work with GitLab merge requests, CI/CD pipelines, issues, releases, or make API requests. Supports gitlab.com and self-hosted instances.
---

# GitLab Skill

Use the `glab` CLI to interact with GitLab. Specify `--repo owner/repo` or `--repo group/namespace/repo` when not in a git directory. Also accepts full URLs.

> ⚠️ **Настройка / новый токен / ротация — иди в [SETUP.md](./SETUP.md).**
> Этот файл — только про работу с уже подключённым GitLab.
> `GITLAB_HOST` уже в `openclaw.json` — тебе его не настраивать и не
> переспрашивать у пользователя.

## Boilerplate for every call

Each `exec` tool call starts a fresh shell — re-read credentials from the
config every time:

```bash
CFG=/root/.openclaw/openclaw.json
export GITLAB_HOST=$(jq -r '.skills.entries.glab.env.GITLAB_HOST // empty' "$CFG")
export GITLAB_TOKEN=$(jq -r '.skills.entries.glab.env.GITLAB_TOKEN // empty' "$CFG")

glab mr list --repo group/project
```

Fresh env from config → always uses current token. **No gateway restart needed.**

If a call fails with auth error (401/403), the token is missing or expired —
go to [SETUP.md](./SETUP.md) for rotation, don't invent steps.

**Never echo the token back to the user.**

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

## Find MRs that need your attention

To find MRs where you're involved, **don't roll your own filter** —
GitLab's `scope` parameter handles it. Three canonical scopes:

| Scope            | What it returns                              |
| ---------------- | -------------------------------------------- |
| `created_by_me`  | MRs you opened                               |
| `assigned_to_me` | MRs where you're an assignee                 |
| `reviews_for_me` | MRs where you're assigned as a **reviewer**  |

### Global search (across every project you have access to)

```bash
# All MRs awaiting your review:
glab api 'merge_requests?scope=reviews_for_me&state=opened&per_page=50' \
  | jq -r '.[] | "\(.web_url) — \(.title)"'

# MRs you opened that are still open:
glab api 'merge_requests?scope=created_by_me&state=opened&per_page=50' \
  | jq -r '.[] | "\(.web_url) — \(.title)"'
```

### Per-repo (when scope is fixed)

`glab mr list` accepts `--reviewer`, `--assignee`, `--author` with
`@me` shorthand:

```bash
glab mr list --reviewer @me --repo group/project
glab mr list --assignee @me --repo group/project
```

> **Antipattern**: querying `merge_requests` without `scope` and writing
> a hand-rolled jq filter on `.author.username` / `.assignees[]` /
> `.reviewers[]`. It's easy to miss one of the three arrays — exactly
> the bug the `scope` parameter was added to prevent.

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
