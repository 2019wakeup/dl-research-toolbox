#!/usr/bin/env python3
"""Probe dataset download environments and validate mirror manifests."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


COMMANDS = [
    "curl",
    "wget",
    "aria2c",
    "git",
    "git-lfs",
    "hf",
    "modelscope",
    "openxlab",
    "kaggle",
    "dvc",
    "datalad",
    "rclone",
]

DEFAULT_URLS = [
    "https://huggingface.co",
    "https://modelscope.cn",
    "https://opendatalab.com",
]

PROXY_KEYS = [
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "no_proxy",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "NO_PROXY",
]


def redact_url(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.username or parsed.password:
        host = parsed.hostname or ""
        if parsed.port:
            host = f"{host}:{parsed.port}"
        return urlunsplit((parsed.scheme, f"***:***@{host}", parsed.path, parsed.query, parsed.fragment))
    return value


def run_command(args: list[str], timeout: int) -> dict:
    started = time.time()
    try:
        proc = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return {
            "command": args,
            "returncode": proc.returncode,
            "seconds": round(time.time() - started, 3),
            "stdout": proc.stdout[-2000:],
            "stderr": proc.stderr[-2000:],
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "command": args,
            "returncode": 124,
            "seconds": round(time.time() - started, 3),
            "stdout": (exc.stdout or "")[-2000:] if isinstance(exc.stdout, str) else "",
            "stderr": "timeout",
        }


def command_version(command: str) -> dict:
    path = shutil.which(command)
    result = {"command": command, "path": path, "available": bool(path)}
    if not path:
        return result
    version_args = [command, "--version"]
    if command == "git-lfs":
        version_args = ["git", "lfs", "version"]
    probe = run_command(version_args, timeout=5)
    first = (probe["stdout"] or probe["stderr"]).splitlines()
    result["version"] = first[0] if first else ""
    return result


def probe(args: argparse.Namespace) -> int:
    report = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "python": sys.version.split()[0],
        "cwd": str(Path.cwd()),
        "commands": [command_version(cmd) for cmd in COMMANDS],
        "proxy_env": {
            key: redact_url(os.environ[key])
            for key in PROXY_KEYS
            if key in os.environ and os.environ[key]
        },
        "live": [],
    }

    urls = args.url or DEFAULT_URLS

    if args.live:
        if not shutil.which("curl"):
            print("curl is required for --live probing", file=sys.stderr)
            return 2
        for url in urls:
            report["live"].append(
                {
                    "url": url,
                    "via_env_proxy": run_command(["curl", "-I", "--max-time", str(args.timeout), url], args.timeout + 2),
                    "direct_no_proxy": run_command(
                        ["curl", "--noproxy", "*", "-I", "--max-time", str(args.timeout), url],
                        args.timeout + 2,
                    ),
                }
            )

    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


def file_hash(path: Path, algorithm: str) -> str:
    h = hashlib.new(algorithm)
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def manifest(args: argparse.Namespace) -> int:
    root = Path(args.path).resolve()
    if not root.exists():
        print(f"path does not exist: {root}", file=sys.stderr)
        return 2
    if args.hash and args.hash not in hashlib.algorithms_available:
        print(f"unsupported hash algorithm: {args.hash}", file=sys.stderr)
        return 2

    rows = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = path.relative_to(root).as_posix()
        stat = path.stat()
        row = {"path": rel, "size": stat.st_size}
        if args.hash:
            row[args.hash] = file_hash(path, args.hash)
        rows.append(row)

    out = Path(args.output)
    with out.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"wrote {len(rows)} entries to {out}")
    return 0


def read_manifest(path: str) -> dict[str, dict]:
    result = {}
    with Path(path).open("r", encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            if "path" not in row or "size" not in row:
                raise ValueError(f"{path}:{lineno} missing path or size")
            result[row["path"]] = row
    return result


def hash_key(row: dict) -> str | None:
    for key in ("sha256", "sha1", "md5", "blake2b"):
        if key in row:
            return key
    return None


def compare(args: argparse.Namespace) -> int:
    official = read_manifest(args.official)
    mirror = read_manifest(args.mirror)

    official_paths = set(official)
    mirror_paths = set(mirror)
    common = official_paths & mirror_paths
    missing = sorted(official_paths - mirror_paths)
    extra = sorted(mirror_paths - official_paths)

    mismatches = []
    for path in sorted(common):
        left = official[path]
        right = mirror[path]
        if left["size"] != right["size"]:
            mismatches.append({"path": path, "reason": "size", "official": left["size"], "mirror": right["size"]})
            continue
        key = hash_key(left)
        if key and key in right and left[key] != right[key]:
            mismatches.append({"path": path, "reason": key, "official": left[key], "mirror": right[key]})

    coverage = len(common) / len(official_paths) if official_paths else 1.0
    ok = not mismatches
    if args.mode == "exact":
        ok = ok and not missing and not extra
    elif args.mode == "subset":
        ok = ok and not extra and coverage >= args.min_coverage
    elif args.mode == "superset":
        ok = ok and not missing
    elif args.mode == "overlap":
        ok = ok and coverage >= args.min_coverage

    summary = {
        "mode": args.mode,
        "official_files": len(official_paths),
        "mirror_files": len(mirror_paths),
        "common_files": len(common),
        "coverage_of_official": round(coverage, 6),
        "missing_from_mirror": missing[:50],
        "extra_in_mirror": extra[:50],
        "mismatches": mismatches[:50],
        "ok": ok,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if ok else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_probe = sub.add_parser("probe", help="inspect downloader tools and optional network reachability")
    p_probe.add_argument("--live", action="store_true", help="run live curl HEAD checks")
    p_probe.add_argument("--url", action="append", help="URL to probe; can be repeated")
    p_probe.add_argument("--timeout", type=int, default=10)
    p_probe.add_argument("--output")
    p_probe.set_defaults(func=probe)

    p_manifest = sub.add_parser("manifest", help="create a JSONL file manifest")
    p_manifest.add_argument("path")
    p_manifest.add_argument("--hash", choices=sorted(hashlib.algorithms_available), help="optional content hash")
    p_manifest.add_argument("--output", required=True)
    p_manifest.set_defaults(func=manifest)

    p_compare = sub.add_parser("compare", help="compare official and mirror manifests")
    p_compare.add_argument("official")
    p_compare.add_argument("mirror")
    p_compare.add_argument("--mode", choices=["exact", "subset", "superset", "overlap"], default="exact")
    p_compare.add_argument("--min-coverage", type=float, default=0.98)
    p_compare.set_defaults(func=compare)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
