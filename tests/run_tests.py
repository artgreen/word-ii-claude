#!/usr/bin/env python3
"""Word II unit-test runner (py65 tier).

Discovers test_*.py modules in this directory and runs every `test_*`
function. Each test raises AssertionError on failure. Run with the
6502-codegen venv:

    ~/.claude/skills/6502-codegen/.venv/bin/python tests/run_tests.py
"""
import importlib
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def main():
    files = sorted(f for f in os.listdir(HERE)
                   if f.startswith("test_") and f.endswith(".py"))
    passed = failed = 0
    fails = []
    for f in files:
        mod = importlib.import_module(f[:-3])
        for name in sorted(dir(mod)):
            if not name.startswith("test_"):
                continue
            fn = getattr(mod, name)
            if not callable(fn):
                continue
            try:
                fn()
                passed += 1
                print(f"  ok   {f}:{name}")
            except Exception as e:  # noqa: BLE001
                failed += 1
                fails.append((f, name, e, traceback.format_exc()))
                print(f"  FAIL {f}:{name}: {e}")
    print(f"\n{passed} passed, {failed} failed")
    if failed:
        print("\n--- failure detail ---")
        for f, name, e, tb in fails:
            print(f"\n{f}:{name}\n{tb}")
        sys.exit(1)


if __name__ == "__main__":
    main()
