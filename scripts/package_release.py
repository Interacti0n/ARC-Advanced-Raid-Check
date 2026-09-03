"""Validate and package ARC using only Python's standard library; never edit sources."""
import argparse
import hashlib
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"


def read(root, name):
    return (root / name).read_text(encoding="utf-8-sig")


def manifest(root, tag=""):
    toc = read(root, "ARC.toc")
    match = re.search(r"^## Version:\s*(\S+)\s*$", toc, re.M)
    if not match or not re.fullmatch(VERSION, match[1]):
        raise ValueError("ARC.toc must have a numeric major.minor.patch version")
    version = match[1]
    if tag and tag != "v" + version:
        raise ValueError(f"Release tag {tag!r} must equal v{version}; update sources before tagging")
    core = re.search(r'ARC\.VERSION\s*=\s*"([^"]+)"', read(root, "ARC_Core.lua"))
    if not core or core[1] != version:
        raise ValueError("Core and TOC versions differ")
    if f"Current version: **{version}**" not in read(root, "README.md"):
        raise ValueError("README version differs from TOC")
    sections = re.split(r"(?m)^v(\d+\.\d+\.\d+) CHANGES\s*\n", read(root, "changelog.txt"))
    if len(sections) < 3 or sections[0].strip() or sections[1] != version or not sections[2].strip():
        raise ValueError("The first changelog section must describe the TOC version")
    modules = [line.strip() for line in toc.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if not modules or modules[0] != "ARC_Core.lua" or modules[-1] != "ARC.lua" or "ARC_PlayerCheck.lua" not in modules:
        raise ValueError("Invalid ARC.toc module order or missing player-check module")
    if len(modules) != len(set(modules)) or any(not re.fullmatch(r"ARC(?:_[A-Za-z]+)?\.lua", name) for name in modules):
        raise ValueError("TOC must contain unique ARC Lua filenames, not paths")
    # The install ZIP deliberately excludes README, docs, tests and build tooling.
    # The third-party catalog's MIT notice is also embedded in ARC_Gear.lua.
    names = ["ARC.toc", *modules, "changelog.txt", "LICENSE"]
    for name in names:
        path = root / name
        if not path.is_file() or path.is_symlink() or root.resolve() not in path.resolve().parents:
            raise ValueError(f"Missing or unsafe package source: {name}")
    notes = "# ARC — Advanced Raid Check " + version + "\n\n" + sections[2].strip() + (
        "\n\nInstall the attached ARC ZIP into Interface/AddOns (ARC/ARC.toc). "
        "Fully exit and restart WoW after updating; /reload may retain an old file list.\n"
    )
    return version, names, notes


def package(root=ROOT, output=None, tag=""):
    root = Path(root).resolve()
    version, names, notes = manifest(root, tag)
    output = Path(output) if output else root / "build"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"ARC-{version}.zip"
    # Fixed timestamps/order/newlines make reruns and Windows/Linux builds identical.
    payloads = {"ARC/" + name: read(root, name).encode("utf-8") for name in sorted(names)}
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zip_file:
        for name, content in payloads.items():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zip_file.writestr(info, content, compresslevel=9)
    with zipfile.ZipFile(archive) as zip_file:
        if zip_file.testzip() or set(zip_file.namelist()) != set(payloads):
            raise ValueError("ZIP verification failed")
        for name, content in payloads.items():
            if zip_file.read(name) != content:
                raise ValueError(f"ZIP content mismatch: {name}")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8", newline="\n")
    (output / "release-notes.md").write_text(notes, encoding="utf-8", newline="\n")
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="", help="Require a release tag exactly matching v<TOC version>")
    parser.add_argument("--output", type=Path, help="Build directory (default: build/)")
    args = parser.parse_args()
    try:
        result = package(output=args.output, tag=args.tag)
    except (ValueError, OSError) as error:
        parser.exit(1, f"Release packaging failed: {error}\n")
    print(f"Verified package: {result}")
