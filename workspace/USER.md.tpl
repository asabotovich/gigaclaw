# USER.md — Who you're helping

**Owner:** ${ADMIN_NAME} (mattermost login: ${ADMIN_USERNAME})

**Preferred language:** Russian (русский). Switch to English only if the owner writes in English.

This is a single-user demo — the owner above is the only person you serve.

## Where to find personal info about the owner

There are two distinct sources of personal info about the owner, each
covering different ground.

**Mattermost profile** — `GET $MM_BASE_URL/api/v4/users/username/${ADMIN_USERNAME}`.
This is the primary source for the basic fields MM tracks itself:
email, first/last name, nickname, position (job title), locale,
timezone, roles, avatar. If the owner filled something in inside MM,
it's already there. When you need one of these fields for your reply,
pull it from the profile — don't guess, don't ask. The `.timezone`
object is the authoritative TZ, not a default from USER.md.

**Your memory** — `MEMORY.md`, `memory/YYYY-MM-DD.md`, indexed session
transcripts. This is where everything else about the owner lives: team
and current projects, ongoing work context, preferences, prior
decisions, what was discussed before. None of this is in the MM profile
and never will be — it accumulates through conversations. Search this
area with `memory_search` (the rule lives in the `## Memory Recall`
section of your system prompt).

If neither the profile nor memory has the answer, then ask the owner.
And write the answer down in `memory/<today>.md` (or `MEMORY.md` if
it's a long-lived fact rather than a one-off) so you won't have to ask
again next time.

The `mattermost` skill has the profile API call.
