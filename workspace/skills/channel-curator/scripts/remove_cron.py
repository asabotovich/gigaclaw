#!/usr/bin/env python3
"""
Удалить все cron-задачи курируемого проекта.

Находит все jobs с name == `curator-<slug>` и удаляет каждый.
Идемпотентно — если их нет, успешно завершается (exit 0).

Usage:
    python3 remove_cron.py --slug <slug>

Stdout: список удалённых id (по одному на строку).
Exit code: 0 — успех (даже если ничего не было). Не-0 — ошибка
выполнения openclaw cli.
"""
import argparse
import json
import shutil
import subprocess
import sys


def run(cmd: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def find_all(name: str) -> list[str]:
    """Find all cron jobs with this name. Return list of ids."""
    rc, out, err = run(["openclaw", "cron", "list", "--json"])
    if rc != 0:
        print(f"openclaw cron list failed: {err.strip()}", file=sys.stderr)
        sys.exit(rc or 1)
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        print(f"openclaw cron list returned non-JSON: {out!r}", file=sys.stderr)
        sys.exit(2)
    return [j["id"] for j in data.get("jobs", []) if j.get("name") == name and j.get("id")]


def remove(job_id: str) -> bool:
    """Remove one cron job. Returns True on success."""
    rc, out, err = run(["openclaw", "cron", "rm", job_id])
    if rc != 0:
        print(f"openclaw cron rm {job_id} failed: {err.strip()}", file=sys.stderr)
        return False
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slug", required=True, help="Project slug (kebab-case)")
    args = parser.parse_args()

    if not shutil.which("openclaw"):
        print("openclaw CLI not found in PATH", file=sys.stderr)
        sys.exit(127)

    name = f"curator-{args.slug}"
    ids = find_all(name)
    if not ids:
        return  # nothing to do, exit 0

    failed = 0
    for job_id in ids:
        if remove(job_id):
            print(job_id)
        else:
            failed += 1

    if failed:
        sys.exit(4)


if __name__ == "__main__":
    main()
