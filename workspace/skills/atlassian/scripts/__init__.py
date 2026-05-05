"""Atlassian Skills Scripts.

This package contains self-contained Python scripts for Jira and Confluence integration.
Each script includes all necessary dependencies inline.
"""

import json
import os

__version__ = "1.0.0"


def _autoload_env_from_openclaw_config() -> None:
    """Sync os.environ from skills.entries.atlassian.env in openclaw.json.

    Why: OpenClaw injects skill env into the gateway process at startup. After
    `openclaw config set skills.entries.atlassian.env.<KEY>` the file is
    updated but the gateway's process.env still holds the old snapshot, so a
    fresh shell spawned by the next skill call inherits stale values. Reading
    the file on every package import keeps env in lockstep with the config
    without requiring a gateway restart.

    The config is the single source of truth for known keys. We never delete
    entries already in os.environ — that lets host-supplied env (e.g.
    HTTPS_PROXY for the SOCKS tunnel) survive untouched.
    """
    cfg_path = os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json")
    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        env_block = cfg["skills"]["entries"]["atlassian"]["env"]
    except (KeyError, OSError, json.JSONDecodeError):
        return
    for key, value in env_block.items():
        text = str(value).strip()
        if text:
            os.environ[key] = text


_autoload_env_from_openclaw_config()
