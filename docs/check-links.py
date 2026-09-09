#!/usr/bin/env python3
"""Check local Markdown paths and heading anchors without third-party modules."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"(?<!!)\[[^]]*\]\(([^)\s]+)(?:\s+[^)]*)?\)")
HEADING = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$")


def markdown_files() -> tuple[Path, ...]:
    """Return project Markdown, excluding ignored vendored/build payloads."""
    result = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "--", "*.md"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return tuple(
            ROOT / path
            for path in result.stdout.splitlines()
            if path and not path.startswith("guest/vendor/")
        )
    return tuple(ROOT.rglob("*.md"))


def slug(text: str) -> str:
    text = re.sub(r"`([^`]*)`", r"\1", text).strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    return re.sub(r"[\s-]+", "-", text).strip("-")


def anchors(path: Path) -> set[str]:
    result: set[str] = set()
    counts: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = HEADING.match(line)
        if not match:
            continue
        base = slug(match.group(1))
        count = counts.get(base, 0)
        counts[base] = count + 1
        result.add(base if count == 0 else f"{base}-{count}")
    return result


def local_target(source: Path, raw: str) -> tuple[Path, str]:
    target, separator, anchor = unquote(raw).partition("#")
    if not target:
        return source, anchor
    return (source.parent / target).resolve(), anchor


def main() -> int:
    failures: list[str] = []
    markdown = markdown_files()
    for source in markdown:
        text = source.read_text(encoding="utf-8")
        for match in LINK.finditer(text):
            raw = match.group(1)
            if raw.startswith(("https://", "http://", "mailto:", "tel:")):
                continue
            target, anchor = local_target(source, raw)
            if not target.exists():
                failures.append(f"{source.relative_to(ROOT)}: missing {raw}")
                continue
            if anchor and target.suffix.lower() == ".md" and anchor not in anchors(target):
                failures.append(f"{source.relative_to(ROOT)}: missing anchor {raw}")
    if failures:
        print("Markdown link check failed:", file=sys.stderr)
        print("\n".join(f"- {item}" for item in failures), file=sys.stderr)
        return 1
    print(f"Markdown link check passed for {len(markdown)} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
