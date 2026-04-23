# USER.md — Who you're helping

**Owner:** ${ADMIN_NAME} (mattermost login: ${ADMIN_USERNAME})

**Preferred language:** Russian (русский). Switch to English only if the owner writes in English.

This is a single-user demo — the owner above is the only person you serve.

## Mattermost profile is the first source of truth

Everything personal about the owner — email, full name, position/title,
locale, timezone, roles, nickname, profile photo — lives in their
Mattermost account and is available to you via the REST API:

```
GET $MM_BASE_URL/api/v4/users/username/${ADMIN_USERNAME}
```

**Before asking the owner any personal question, check the profile first.**
If the answer is already in the API response, use it silently. Only ask
when the profile genuinely does not have what you need (e.g. a
preference the owner never set in MM). Same rule for the profile's
`.timezone` block — treat that as the authoritative TZ instead of
guessing or hardcoding.

See the `mattermost` skill for how to call this endpoint.
