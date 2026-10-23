#!/usr/bin/env python3
"""Package exported desktop programs and Source using centralized identity."""

import argparse
import configparser
import hashlib
import json
import re
from datetime import date
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


PROJECT = Path(__file__).resolve().parents[1]
SOURCE_EXCLUSIONS = {".godot", ".git", "builds", "tests", "validation", "__pycache__"}


def files_under(folder):
    for path in sorted(folder.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(folder)
        if any(part.startswith(".") for part in relative.parts) and relative.name != ".editorconfig":
            continue
        if any(part in SOURCE_EXCLUSIONS for part in relative.parts):
            continue
        if path.name.endswith((".pyc", ".tmp", ".bak")) or "-RECORD-" in path.name:
            continue
        yield path, relative


def put(archive, name, data, executable=False):
    item = ZipInfo(str(name).replace("\\", "/"))
    item.create_system = 3
    item.external_attr = (0o100755 if executable else 0o100644) << 16
    item.compress_type = ZIP_DEFLATED
    archive.writestr(item, data)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()
    date.fromisoformat(args.date)
    output = args.output.resolve()
    if output == PROJECT or PROJECT in output.parents:
        parser.error("The output directory must be outside the Source project.")
    identity = configparser.ConfigParser(interpolation=None)
    identity.read(PROJECT / "config/branding.cfg", encoding="utf-8")
    name = json.loads(identity["branding"]["project_name"])
    stem = json.loads(identity["branding"]["artifact_stem"])
    version = (PROJECT / "VERSION.txt").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,95}", stem):
        parser.error("Invalid branding/artifact_stem.")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.+-]+)?", version):
        parser.error("Invalid VERSION.txt.")
    prefix = f"{stem}_{version}"
    targets = [output / f"{prefix}_{kind}.zip" for kind in
               ("Source", "Windows_x86_64", "Linux_x86_64")]
    notes_path = output / f"{prefix}_Release_Notes.md"
    if any(path.exists() for path in targets + [notes_path]):
        parser.error("A delivery file already exists; choose a new output directory.")
    for platform, extension in (("windows", ".exe"), ("linux", ".x86_64")):
        binary = PROJECT / "builds" / platform / (stem + extension)
        if not binary.is_file() or binary.stat().st_size == 0:
            parser.error(f"Export the release program first: {binary}")
    notes = (PROJECT / "docs/RELEASE_NOTES.md").read_text(encoding="utf-8")
    output.mkdir(parents=True, exist_ok=True)
    with ZipFile(targets[0], "w") as archive:
        for path, relative in files_under(PROJECT):
            put(archive, Path(f"{stem}_v{version}") / relative, path.read_bytes())
    for target, platform, label, extension in zip(
        targets[1:], ("windows", "linux"), ("Windows", "Linux"), (".exe", ".x86_64")
    ):
        root = Path(f"{prefix}_{label}_x86_64")
        binary_name = stem + extension
        launch = (f"双击 `{binary_name}` 启动。" if platform == "windows" else
                  f"在本目录执行 `chmod +x {binary_name}`，然后执行 `./{binary_name}`。")
        readme = (f"# {name} {version} — {label} x86_64\n\n{launch}\n\n"
                  "程序包含运行资源，无需安装或打开 Godot 编辑器。\n\n"
                  "将 examples 复制到可写目录，在程序中选择该内容目录后打开 .dtl 示例。\n\n"
                  "本版本未执行应用启动、功能或回归测试。\n\n"
                  "功能、限制与操作方法见 USER_GUIDE.md；版本说明见 RELEASE_NOTES.md；"
                  "第三方声明见 THIRD_PARTY_NOTICES.md 和 third_party/。\n")
        with ZipFile(target, "w") as archive:
            for path, relative in files_under(PROJECT / "builds" / platform):
                if not relative.name.startswith(stem):
                    raise ValueError(f"Unexpected export file: {relative}")
                executable = platform == "linux" and (relative.name == binary_name or relative.suffix == ".sh")
                put(archive, root / relative, path.read_bytes(), executable)
            put(archive, root / "README.md", readme.encode())
            put(archive, root / "USER_GUIDE.md", (PROJECT / "README.md").read_bytes())
            put(archive, root / "CHANGELOG.md", (PROJECT / "CHANGELOG.md").read_bytes())
            put(archive, root / "RELEASE_NOTES.md", notes.encode())
            notices = (f"# {name} 第三方声明\n\n"
                       "依赖版本与许可见 [依赖和许可说明](docs/DEPENDENCIES.md)。\n\n"
                       "完整许可证与组件声明位于 `third_party/`。\n")
            put(archive, root / "THIRD_PARTY_NOTICES.md", notices.encode())
            for folder in ("examples", "third_party", "docs"):
                for path, relative in files_under(PROJECT / folder):
                    put(archive, root / folder / relative, path.read_bytes())
    table = ["\n## 交付文件信息\n", f"打包日期：{args.date}\n",
             "| 文件 | 字节数 | SHA256 |", "|---|---:|---|"]
    for path in targets:
        table.append(f"| {path.name} | {path.stat().st_size} | `{digest(path)}` |")
    notes_path.write_text(notes.rstrip() + "\n" + "\n".join(table) + "\n", encoding="utf-8")
    for path in targets + [notes_path]:
        print(f"{path.name}\t{path.stat().st_size}\t{digest(path)}")


if __name__ == "__main__":
    main()
