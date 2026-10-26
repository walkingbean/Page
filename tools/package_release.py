#!/usr/bin/env python3
"""Package the three product archives using centralized product identity."""

import argparse
import configparser
import hashlib
import json
import os
import re
import shutil
import tempfile
from datetime import date
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


PROJECT = Path(__file__).resolve().parents[1]
SOURCE_EXCLUSIONS = {
    ".godot", ".git", "builds", "tests", "qa", "validation",
    "evidence", "test-results", "__pycache__",
}
SOURCE_ONLY_DOCUMENTS = {"RELEASE_NOTES.md", "ROADMAP.md", "TESTCASES.md", "DELIVERY_RULES.md"}


def files_under(folder):
    for path in sorted(folder.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(folder)
        if any(part.startswith(".") for part in relative.parts) and relative.name != ".editorconfig":
            continue
        if any(part in SOURCE_EXCLUSIONS for part in relative.parts):
            continue
        if path.name.endswith((".pyc", ".tmp", ".bak", ".log")):
            continue
        if path.name.lower() == "test_progress.zip" or path.name.lower().endswith("_test_progress.zip"):
            continue
        if "-RECORD-" in path.name or path.name.endswith(("_Progress.md", "_Results.md")):
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


def read_required(relative):
    path = PROJECT / relative
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"Missing required release input: {relative}")
    return path.read_bytes()


def inspect_exports(stem):
    exports = {}
    for platform, extension, signature in (
        ("windows", ".exe", b"MZ"), ("linux", ".x86_64", b"\x7fELF")
    ):
        folder = PROJECT / "builds" / platform
        binary = folder / (stem + extension)
        if not binary.is_file() or binary.is_symlink():
            raise ValueError(f"Export the release program first: {binary}")
        with binary.open("rb") as source:
            if source.read(len(signature)) != signature:
                raise ValueError(f"Invalid {platform} executable signature: {binary}")
        entries = list(files_under(folder))
        if any(not relative.name.startswith(stem) for _, relative in entries):
            raise ValueError(f"Unexpected file in {folder}; use a clean export directory.")
        exports[platform] = entries
    return exports


def package_platform(target, platform, label, extension, name, stem, version, exports, documents):
    root = Path(f"{stem}_{version}_{label}_x86_64")
    binary_name = stem + extension
    launch = (
        f"双击 `{binary_name}` 启动。" if platform == "windows" else
        f"在本目录执行 `./{binary_name}`。若解压工具未保留执行权限，先执行 `chmod +x {binary_name}`。"
    )
    readme = (
        f"# {name} {version} — {label} x86_64\n\n{launch}\n\n"
        "程序包含运行资源，无需安装或打开 Godot 编辑器。需要图形桌面和兼容的图形驱动。\n\n"
        "将 examples/text_style_story、examples/portrait_story 或 examples/flow_story 复制到可写目录，"
        "在程序中选择该示例目录为 Content Folder，再打开其中的 .dtl。\n\n"
        "发布说明、路线图及完整测试清单位于同版本 Source 包的 docs/ 中。"
        "独立测试进度包提供实际执行证据；Windows 实机验证依约延期至 1.0.0。\n\n"
        "功能、边界与操作见 USER_GUIDE.md；第三方声明见 THIRD_PARTY_NOTICES.md 和 third_party/。\n"
    )
    with ZipFile(target, "x") as archive:
        for path, relative in exports[platform]:
            executable = platform == "linux" and (relative.name == binary_name or relative.suffix == ".sh")
            put(archive, root / relative, path.read_bytes(), executable)
        put(archive, root / "README.md", readme.encode("utf-8"))
        put(archive, root / "USER_GUIDE.md", ("# 使用说明\n\n请阅读 [完整使用说明](docs/README.md)。\n").encode("utf-8"))
        put(archive, root / "CHANGELOG.md", documents["CHANGELOG.md"])
        notices = (
            f"# {name} 第三方声明\n\n"
            "依赖版本与许可见 [依赖和许可说明](docs/DEPENDENCIES.md)。\n\n"
            "完整许可证与组件声明位于 `third_party/`。\n"
        )
        put(archive, root / "THIRD_PARTY_NOTICES.md", notices.encode("utf-8"))
        for folder in ("examples", "third_party", "docs"):
            for path, relative in files_under(PROJECT / folder):
                if folder == "docs" and relative.name in SOURCE_ONLY_DOCUMENTS:
                    continue
                put(archive, root / folder / relative, path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()
    try:
        date.fromisoformat(args.date)
        output = args.output.resolve()
        if output == PROJECT or PROJECT in output.parents:
            raise ValueError("The output directory must be outside the Source project.")
        identity = configparser.ConfigParser(interpolation=None)
        identity.read(PROJECT / "config/branding.cfg", encoding="utf-8")
        name = json.loads(identity["branding"]["project_name"])
        stem = json.loads(identity["branding"]["artifact_stem"])
        version = (PROJECT / "VERSION.txt").read_text(encoding="utf-8").strip()
        if not isinstance(name, str) or not name.strip() or len(name) > 160 or any(c in name for c in "\r\n"):
            raise ValueError("Invalid branding/project_name.")
        if not isinstance(stem, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,95}", stem):
            raise ValueError("Invalid branding/artifact_stem.")
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.+-]+)?", version):
            raise ValueError("Invalid VERSION.txt.")
        prefix = f"{stem}_{version}"
        filenames = [
            f"{prefix}_Source.zip",
            f"{prefix}_Windows_x86_64.zip",
            f"{prefix}_Linux_x86_64.zip",
        ]
        if any(os.path.lexists(output / filename) for filename in filenames):
            raise ValueError("A delivery file already exists; choose a new output directory.")
        documents = {relative: read_required(relative) for relative in (
            "README.md", "docs/README.md", "CHANGELOG.md", "docs/RELEASE_NOTES.md",
            "docs/ROADMAP.md", "docs/TESTCASES.md", "docs/DEPENDENCIES.md",
        )}
        exports = inspect_exports(stem)
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".page-release-", dir=output) as staging:
            stage = Path(staging)
            with ZipFile(stage / filenames[0], "x") as archive:
                for path, relative in files_under(PROJECT):
                    put(archive, Path(f"{stem}_v{version}") / relative, path.read_bytes())
            for index, platform, label, extension in (
                (1, "windows", "Windows", ".exe"), (2, "linux", "Linux", ".x86_64")
            ):
                package_platform(stage / filenames[index], platform, label, extension,
                                 name, stem, version, exports, documents)
            created = []
            try:
                for filename in filenames:
                    destination = output / filename
                    with destination.open("xb") as target:
                        created.append(destination)
                        with (stage / filename).open("rb") as source:
                            shutil.copyfileobj(source, target)
                        target.flush()
                        os.fsync(target.fileno())
            except Exception:
                for path in created:
                    path.unlink(missing_ok=True)
                raise
        for filename in filenames:
            path = output / filename
            print(f"{filename}\t{path.stat().st_size}\t{digest(path)}")
    except (OSError, ValueError, KeyError, configparser.Error) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
