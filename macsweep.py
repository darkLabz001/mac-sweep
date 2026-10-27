#!/usr/bin/env python3
"""A small, conservative macOS storage cleaner."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Candidate:
    path: Path
    category: str
    size: int
    modified: float


def category_roots(home: Path) -> dict[str, Path]:
    return {
        "caches": home / "Library" / "Caches",
        "logs": home / "Library" / "Logs",
        "downloads": home / "Downloads",
    }


def file_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def scan(home: Path, categories: set[str], older_than_days: int) -> list[Candidate]:
    roots = category_roots(home)
    cutoff = time.time() - older_than_days * 86400
    candidates: list[Candidate] = []
    for category in categories:
        root = roots[category]
        if not root.is_dir():
            continue
        for current, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [name for name in dirs if not (Path(current) / name).is_symlink()]
            for name in files:
                path = Path(current) / name
                try:
                    stat = path.stat()
                except OSError:
                    continue
                if path.is_symlink() or stat.st_mtime > cutoff:
                    continue
                candidates.append(Candidate(path, category, stat.st_size, stat.st_mtime))
    return sorted(candidates, key=lambda item: item.size, reverse=True)


def human_size(value: int) -> str:
    units = ("B", "KB", "MB", "GB", "TB")
    size = float(value)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            return f"{size:.1f} {unit}"
        size /= 1024
    return "0.0 B"


def trash_path(path: Path, home: Path) -> Path:
    trash = home / ".Trash"
    trash.mkdir(exist_ok=True)
    destination = trash / path.name
    counter = 1
    while destination.exists():
        destination = trash / f"{path.stem} ({counter}){path.suffix}"
        counter += 1
    return destination


def move_to_trash(candidate: Candidate, home: Path) -> None:
    destination = trash_path(candidate.path, home)
    shutil.move(str(candidate.path), str(destination))


def print_report(candidates: list[Candidate]) -> None:
    total = sum(item.size for item in candidates)
    print(f"Found {len(candidates)} files totaling {human_size(total)}")
    if not candidates:
        return
    print("\nSIZE       CATEGORY   PATH")
    print("---------- ---------- ----------------------------------------")
    for item in candidates:
        print(f"{human_size(item.size):<10} {item.category:<10} {item.path}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Safely find reclaimable files on your Mac.")
    parser.add_argument("command", choices=("scan", "clean"), nargs="?", default="scan")
    parser.add_argument("--category", choices=tuple(category_roots(Path.home())), action="append")
    parser.add_argument("--older-than", type=int, default=30, metavar="DAYS")
    parser.add_argument("--yes", action="store_true", help="move candidates to Trash without prompting")
    args = parser.parse_args(argv)
    if args.older_than < 0:
        parser.error("--older-than must be zero or greater")

    categories = set(args.category or category_roots(Path.home()))
    home = Path.home()
    candidates = scan(home, categories, args.older_than)
    print_report(candidates)
    if args.command == "scan" or not candidates:
        return 0

    if not args.yes:
        answer = input("\nMove these files to Trash? [y/N] ").strip().lower()
        if answer != "y":
            print("Nothing moved.")
            return 0
    moved = 0
    for candidate in candidates:
        try:
            move_to_trash(candidate, home)
            moved += 1
        except OSError as error:
            print(f"Could not move {candidate.path}: {error}", file=sys.stderr)
    print(f"Moved {moved} files to Trash.")
    return 0 if moved == len(candidates) else 1


if __name__ == "__main__":
    raise SystemExit(main())
