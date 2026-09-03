"""Attach an already-tested package using gh; never create releases or replace assets."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from package_release import ROOT, VERSION


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True, encoding="utf-8")


def publish(tag, output=None):
    if not re.fullmatch("v" + VERSION, tag):
        raise ValueError("Expected a numeric v<major>.<minor>.<patch> tag")
    repo = os.environ["GH_REPO"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Invalid repository name")
    output = Path(output) if output else ROOT / "build"
    archive = output / f"ARC-{tag[1:]}.zip"
    assets = [archive, archive.with_suffix(".zip.sha256")]
    release = json.loads(gh("api", f"repos/{repo}/releases/tags/{tag}"))
    if release.get("draft") or release.get("tag_name") != tag:
        raise ValueError("Only the matching, published release may be updated")
    # Preflight every collision before uploading anything. An identical rerun is safe.
    uploads = []
    for path in assets:
        digest = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
        existing = next((asset for asset in release.get("assets", []) if asset["name"] == path.name), None)
        if existing:
            if existing.get("digest") != digest:
                raise ValueError(f"Existing asset {path.name} differs or has no verifiable digest; refusing to replace it")
        else:
            uploads.append(path)
    for path in uploads:
        gh("release", "upload", tag, str(path), "--repo", repo)
    # Preserve all user-written or GitHub-generated notes.
    if not (release.get("body") or "").strip():
        gh("release", "edit", tag, "--repo", repo, "--notes-file", str(output / "release-notes.md"))
    print(f"Verified release assets for {repo} {tag}; existing assets and notes preserved")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: publish_release.py v<version>")
        publish(sys.argv[1])
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Release upload failed: {error}")
