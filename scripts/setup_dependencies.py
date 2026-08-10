#!/usr/bin/env python3
# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# SPDX-License-Identifier: MulanPSL-2.0

from __future__ import annotations

import argparse
import hashlib
import json
import posixpath
import subprocess
import tarfile
import urllib.request
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "config" / "dependencies.lock.json"


def run(*arguments: str) -> None:
    subprocess.run(arguments, check=True)


def install_common(spec: dict[str, str]) -> None:
    destination = ROOT / spec["destination"]
    if not (destination / ".git").is_dir():
        destination.mkdir(parents=True, exist_ok=True)
        run("git", "init", str(destination))
        run("git", "-C", str(destination), "remote", "add", "origin", spec["url"])
    run("git", "-C", str(destination), "fetch", "--depth", "1", "origin", spec["revision"])
    run("git", "-C", str(destination), "checkout", "--detach", "FETCH_HEAD")
    revision = subprocess.run(
        ["git", "-C", str(destination), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if revision != spec["revision"]:
        raise SystemExit(f"Common revision mismatch: {revision}")


def safe_extract(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle.getmembers():
            path = PurePosixPath(member.name)
            if (
                path.is_absolute()
                or ".." in path.parts
                or member.ischr()
                or member.isblk()
                or member.isfifo()
            ):
                raise SystemExit(f"unsafe archive member: {member.name}")
            if member.issym() or member.islnk():
                link = PurePosixPath(member.linkname)
                combined = path.parent / link if member.issym() else link
                normalized = PurePosixPath(posixpath.normpath(str(combined)))
                if link.is_absolute() or normalized.is_absolute() or normalized.parts[:1] == ("..",):
                    raise SystemExit(f"unsafe archive link: {member.name} -> {member.linkname}")
        bundle.extractall(destination)


def install_tool(name: str, spec: dict[str, str]) -> Path:
    downloads = ROOT / "build" / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    archive = downloads / spec["archive"]
    if not archive.is_file():
        urllib.request.urlretrieve(spec["url"], archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != spec["sha256"]:
        raise SystemExit(f"{name} checksum mismatch: {digest}")
    destination = ROOT / "build" / "toolchains" / f"{name}-{spec['version']}"
    marker = destination / ".complete"
    if not marker.is_file() or marker.read_text(encoding="utf-8").strip() != digest:
        destination.mkdir(parents=True, exist_ok=True)
        safe_extract(archive, destination)
        marker.write_text(digest + "\n", encoding="utf-8")
    return destination / spec["path"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Install locked PWM dependencies")
    parser.add_argument("--common", action="store_true")
    parser.add_argument("--tool", action="append", default=[])
    parser.add_argument("--github-path", type=Path)
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    if lock.get("schema_version") != 1:
        raise SystemExit("unsupported dependency lock schema")
    if args.common:
        install_common(lock["sources"]["common"])
    paths = []
    tools = lock["toolchains"]["ubuntu-22.04"]
    for name in args.tool:
        if name not in tools:
            raise SystemExit(f"tool is not locked: {name}")
        paths.append(install_tool(name, tools[name]))
    if args.github_path is not None:
        with args.github_path.open("a", encoding="utf-8") as stream:
            for path in paths:
                stream.write(str(path.resolve()) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
