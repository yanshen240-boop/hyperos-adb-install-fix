#!/usr/bin/env python3
"""把 magisk-module/ 打包成可直接刷入的 Magisk 模块 zip。"""

import os
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "magisk-module"

EXECUTABLE = {".sh", ""}  # "" 指 update-binary
SKIP_NAMES = {"build_module.py"}


def read_module_prop():
    prop = {}
    for line in (SRC / "module.prop").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        prop[k.strip()] = v.strip()
    return prop


def should_exec(rel: Path) -> bool:
    if rel.suffix == ".sh":
        return True
    if rel.name == "update-binary":
        return True
    return False


def main():
    prop = read_module_prop()
    out = ROOT / f"HyperOS-ADB-Install-Fix-{prop['version']}.zip"

    if out.exists():
        out.unlink()

    files = []
    for path in sorted(SRC.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(SRC)
        if path.name in SKIP_NAMES:
            continue
        files.append((path, rel))

    # CRLF 会把 shell 脚本搞坏，写入前统一成 LF
    for path, rel in files:
        if path.suffix in {".sh", ".prop"} or path.name == "update-binary":
            data = path.read_bytes().replace(b"\r\n", b"\n")
            path.write_bytes(data)

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path, rel in files:
            info = zipfile.ZipInfo(rel.as_posix())
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if should_exec(rel) else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.create_system = 3
            zf.writestr(info, path.read_bytes())

    print(f"built: {out}")
    print(f"size : {out.stat().st_size} bytes, {len(files)} entries")
    with zipfile.ZipFile(out) as zf:
        bad = zf.testzip()
        if bad:
            print(f"ZIP CORRUPT at {bad}")
            sys.exit(1)
        for info in zf.infolist():
            mode = (info.external_attr >> 16) & 0o777
            print(f"  {mode:o}  {info.file_size:>6}  {info.filename}")


if __name__ == "__main__":
    main()
