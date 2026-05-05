"""Print every public function exported by this skill, with its signature.

Usage::

    cd /root/.openclaw/workspace/skills/atlassian
    python3 -m scripts._list_functions

The output is generated from the actual code in `scripts/*.py` — never
stale, never lies. If a function isn't here, it doesn't exist; if it's
here, the signature is exactly what the wrapper accepts. Use this
before calling a wrapper if you're not sure of the name or arguments.
"""

import importlib
import inspect
import pkgutil
from pathlib import Path


def _iter_public_functions():
    pkg_dir = Path(__file__).parent
    for _, modname, _ in pkgutil.iter_modules([str(pkg_dir)]):
        if modname.startswith("_"):
            continue
        module = importlib.import_module(f"scripts.{modname}")
        for name, obj in inspect.getmembers(module, inspect.isfunction):
            if name.startswith("_"):
                continue
            if obj.__module__ != module.__name__:
                continue  # re-exports, skip
            yield modname, name, inspect.signature(obj)


def main() -> None:
    last_module = None
    for modname, name, sig in sorted(_iter_public_functions()):
        if modname != last_module:
            if last_module is not None:
                print()
            print(f"# scripts.{modname}")
            last_module = modname
        print(f"{name}{sig}")


if __name__ == "__main__":
    main()
