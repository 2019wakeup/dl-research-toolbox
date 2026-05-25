#!/usr/bin/env python3
"""Guard research workspace memory and experiment layout.

This script is intentionally conservative. It enforces project-memory roots,
upward-sync discipline for staged memory changes, and phase/series/run experiment
layout. It does not inspect or print sensitive dataset contents.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable

CORE_FILES = [
    "info/project_summary.md",
    "info/project_goals.md",
    "info/project_architecture.md",
    "tasks/task_list.md",
    "tasks/task_progress.md",
]
REQUIRED_RUN_FILES = [
    "split.json",
    "run_config.json",
    "summary.json",
    "metrics.jsonl",
    "checkpoint_manifest.json",
]
SKIP_DIRS = {".git", "__pycache__", ".venv", "venv", "node_modules", ".mypy_cache", ".pytest_cache"}
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def add_issue(issues: list[str], msg: str) -> None:
    issues.append(msg)


def git_staged_files(root: Path) -> list[str]:
    try:
        out = subprocess.check_output(
            ["git", "diff", "--cached", "--name-only"], cwd=root, text=True, stderr=subprocess.DEVNULL
        )
    except Exception:
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def iter_dirs(root: Path) -> Iterable[Path]:
    for cur, dirs, _files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        yield Path(cur)


def has_nested_git_ancestor(path: Path, root: Path) -> bool:
    for parent in [path, *path.parents]:
        if parent == root:
            return False
        if (parent / ".git").exists():
            return True
    return False


def init_root(root: Path) -> None:
    (root / "info").mkdir(exist_ok=True)
    (root / "tasks").mkdir(exist_ok=True)
    (root / ".project-memory-root").touch(exist_ok=True)
    for item in CORE_FILES:
        (root / item).touch(exist_ok=True)


def check_core(root: Path, issues: list[str]) -> None:
    if not (root / ".project-memory-root").exists():
        add_issue(issues, "missing .project-memory-root at canonical memory root")
    for item in CORE_FILES:
        if not (root / item).exists():
            add_issue(issues, f"missing core memory file: {item}")


def check_distributed_memory(root: Path, issues: list[str], warnings: list[str]) -> None:
    progress = (root / "tasks/task_progress.md").read_text(errors="ignore") if (root / "tasks/task_progress.md").exists() else ""
    for d in iter_dirs(root):
        if d == root:
            continue
        name = d.name
        marker = None
        if name == "info" and (d / "project_summary.md").exists():
            marker = d
        elif name == "tasks" and (d / "task_list.md").exists():
            marker = d
        if marker is None:
            continue
        if marker.parent == root:
            continue
        r = rel(marker.parent, root)
        if has_nested_git_ancestor(marker, root):
            if r not in progress:
                warnings.append(f"child memory exists but root progress has no sync mention: {r}")
        else:
            add_issue(issues, f"non-root memory directory without child repo boundary: {r}/{name}")


def is_memory_or_domain_change(path: str) -> bool:
    parts = Path(path).parts
    if not parts:
        return False
    if path in {"tasks/task_progress.md", "tasks/task_list.md"}:
        return False
    if parts[0] == "research":
        return True
    return "info" in parts or "tasks" in parts


def check_staged_sync(root: Path, issues: list[str]) -> None:
    staged = git_staged_files(root)
    if not staged:
        return
    touched_domain = [p for p in staged if is_memory_or_domain_change(p)]
    touched_root_sync = any(p in {"tasks/task_progress.md", "tasks/task_list.md"} for p in staged)
    if touched_domain and not touched_root_sync:
        sample = ", ".join(touched_domain[:5])
        add_issue(
            issues,
            "staged child/domain memory changed without root tasks sync; "
            f"also stage tasks/task_progress.md or tasks/task_list.md. changed: {sample}",
        )


def load_index_paths(index_path: Path) -> set[str]:
    paths: set[str] = set()
    if not index_path.exists():
        return paths
    for line_no, line in enumerate(index_path.read_text(errors="ignore").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{index_path}: invalid JSONL line {line_no}: {exc}") from exc
        p = obj.get("path")
        if isinstance(p, str):
            paths.add(p)
    return paths


def run_status(run_dir: Path) -> str:
    summary = run_dir / "summary.json"
    if not summary.exists():
        return "unknown"
    try:
        obj = json.loads(summary.read_text())
    except Exception:
        return "unknown"
    return str(obj.get("status", "unknown"))


def discover_run_dirs(exp: Path) -> list[tuple[str, str, Path]]:
    runs: list[tuple[str, str, Path]] = []
    for phase in sorted([p for p in exp.iterdir() if p.is_dir()]):
        for series in sorted([p for p in phase.iterdir() if p.is_dir()]):
            for run in sorted([p for p in series.iterdir() if p.is_dir()]):
                if any((run / f).exists() for f in REQUIRED_RUN_FILES + ["notes.md", "architecture.md"]):
                    runs.append((phase.name, series.name, run))
    return runs


def rebuild_index(root: Path, exp: Path, runs: list[tuple[str, str, Path]]) -> None:
    rows = []
    for phase, series, run in runs:
        rows.append(
            {
                "run_id": run.name,
                "phase": phase,
                "series": series,
                "path": rel(run, root),
                "status": run_status(run),
                "summary_path": rel(run / "summary.json", root),
            }
        )
    with (exp / "index.jsonl").open("w") as f:
        for row in rows:
            f.write(json.dumps(row, sort_keys=True, ensure_ascii=True) + "\n")


def check_experiments(root: Path, issues: list[str], rebuild: bool) -> None:
    for exp in root.rglob("research/experiments"):
        if any(part in SKIP_DIRS for part in exp.parts):
            continue
        if not exp.is_dir():
            continue
        # Flat run dirs directly under experiments are forbidden.
        for child in sorted([p for p in exp.iterdir() if p.is_dir()]):
            if any((child / f).exists() for f in REQUIRED_RUN_FILES):
                add_issue(issues, f"flat experiment run directory; use <phase>/<series>/<run_id>: {rel(child, root)}")
        runs = discover_run_dirs(exp)
        if not runs:
            continue
        for phase, series, run in runs:
            for slug, label in [(phase, "phase"), (series, "series"), (run.name, "run_id")]:
                if not SLUG_RE.match(slug):
                    add_issue(issues, f"invalid {label} slug '{slug}' in {rel(run, root)}")
            missing = [f for f in REQUIRED_RUN_FILES if not (run / f).exists()]
            if missing:
                add_issue(issues, f"experiment run missing required files {missing}: {rel(run, root)}")
        if rebuild:
            rebuild_index(root, exp, runs)
        index = exp / "index.jsonl"
        if not index.exists():
            add_issue(issues, f"missing experiment index: {rel(index, root)}")
            continue
        try:
            indexed = load_index_paths(index)
        except ValueError as exc:
            add_issue(issues, str(exc))
            continue
        for _phase, _series, run in runs:
            if rel(run, root) not in indexed:
                add_issue(issues, f"experiment run missing from index.jsonl: {rel(run, root)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Guard research memory and experiment layout.")
    parser.add_argument("--root", default=".", help="Workspace root to check")
    parser.add_argument("--init-root", action="store_true", help="Create root marker and core memory files if missing")
    parser.add_argument("--rebuild-experiment-index", action="store_true", help="Rebuild research/experiments/index.jsonl files")
    parser.add_argument("--staged", action="store_true", help="Also enforce staged-change upward sync discipline")
    parser.add_argument("--strict-all-sync", action="store_true", help="Treat unsynced existing child memories as errors")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if args.init_root:
        init_root(root)

    issues: list[str] = []
    warnings: list[str] = []
    check_core(root, issues)
    check_distributed_memory(root, issues, warnings)
    check_staged_sync(root, issues) if args.staged else None
    check_experiments(root, issues, args.rebuild_experiment_index)

    if args.strict_all_sync and warnings:
        issues.extend(warnings)
    for warning in warnings:
        print(f"[warn] {warning}", file=sys.stderr)
    if issues:
        print("Research memory guard failed:", file=sys.stderr)
        for issue in issues:
            print(f"- {issue}", file=sys.stderr)
        print("\nSuggested fixes:", file=sys.stderr)
        print("- python3 <skill>/scripts/research_memory_guard.py --root . --init-root --rebuild-experiment-index", file=sys.stderr)
        print("- add an upward sync entry to tasks/task_progress.md", file=sys.stderr)
        print("- move flat experiment runs to research/experiments/<phase>/<series>/<run_id>/", file=sys.stderr)
        return 1
    print("Research memory guard passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
