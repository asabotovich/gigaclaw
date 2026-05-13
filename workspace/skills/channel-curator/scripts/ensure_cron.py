#!/usr/bin/env python3
"""
Создать (или вернуть существующий) cron-job для курируемого проекта.

Idempotent: если cron с именем `curator-<slug>` уже есть — выводит его
id, новый не создаёт.

Usage:
    python3 ensure_cron.py --slug <slug>
    python3 ensure_cron.py --slug <slug> --schedule "0 9-18 * * *" --tz "Europe/Moscow"

Stdout: id cron-задачи (одной строкой).
Exit code: 0 — успех (job есть/создан), не-0 — ошибка.
"""
import argparse
import json
import shutil
import subprocess
import sys

DEFAULT_SCHEDULE = "0 9-18 * * *"
DEFAULT_TZ = "Europe/Moscow"


def run(cmd: list[str]) -> tuple[int, str, str]:
    """Run subprocess, return (rc, stdout, stderr)."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def find_existing(name: str) -> str | None:
    """Find first existing cron job with this name. Return id or None."""
    rc, out, err = run(["openclaw", "cron", "list", "--json"])
    if rc != 0:
        return None
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return None
    for job in data.get("jobs", []):
        if job.get("name") == name:
            return job.get("id")
    return None


def create(name: str, schedule: str, tz: str, message: str) -> str:
    """Create cron. Return new id."""
    rc, out, err = run([
        "openclaw", "cron", "add",
        "--name", name,
        "--cron", schedule,
        "--tz", tz,
        "--session", "isolated",
        "--no-deliver",
        "--json",
        "--message", message,
    ])
    if rc != 0:
        print(f"openclaw cron add failed: {err.strip()}", file=sys.stderr)
        sys.exit(rc or 1)
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        print(f"openclaw cron add returned non-JSON: {out!r}", file=sys.stderr)
        sys.exit(2)
    job_id = data.get("id")
    if not job_id:
        print(f"openclaw cron add response has no 'id': {data!r}", file=sys.stderr)
        sys.exit(3)
    return job_id


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slug", required=True, help="Project slug (kebab-case)")
    parser.add_argument("--schedule", default=DEFAULT_SCHEDULE, help=f"Cron expression (default: {DEFAULT_SCHEDULE!r})")
    parser.add_argument("--tz", default=DEFAULT_TZ, help=f"Timezone (default: {DEFAULT_TZ!r})")
    args = parser.parse_args()

    if not shutil.which("openclaw"):
        print("openclaw CLI not found in PATH", file=sys.stderr)
        sys.exit(127)

    name = f"curator-{args.slug}"
    message = (
        f"Чек проекта {args.slug}. "
        f"Прочитай ~/.openclaw/workspace/skills/channel-curator/projects/{args.slug}.md "
        f"и действуй по Сценарию B."
    )

    existing = find_existing(name)
    if existing:
        print(existing)
        return

    job_id = create(name, args.schedule, args.tz, message)
    print(job_id)


if __name__ == "__main__":
    main()
