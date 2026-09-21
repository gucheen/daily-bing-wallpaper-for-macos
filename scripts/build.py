import os
import platform
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
APP = BUILD / "Daily Wallpaper.app"
CONTENTS = APP / "Contents"
TIMEOUT_MS = 1_800_000


def run(*args):
    subprocess.run(args, cwd=ROOT, env=build_env, check=True, timeout=TIMEOUT_MS / 1000)


build_env = os.environ.copy()
build_env["CLANG_MODULE_CACHE_PATH"] = str(BUILD / "ModuleCache")
build_env["SWIFT_MODULECACHE_PATH"] = str(BUILD / "ModuleCache")
for directory in (CONTENTS / "MacOS", CONTENTS / "Resources"):
    directory.mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / "Resources/Info.plist", CONTENTS / "Info.plist")
(CONTENTS / "PkgInfo").write_bytes(b"APPL????")
run("swiftc", "-parse-as-library", "-O", "-target", f"{platform.machine()}-apple-macos12.0",
    "DailyWallpaper.swift", "-framework", "AppKit", "-framework", "CoreImage",
    "-o", str(CONTENTS / "MacOS/DailyWallpaper"))
run("swift", "scripts/GenerateIcon.swift", str(BUILD / "AppIcon.iconset"))
run("iconutil", "-c", "icns", str(BUILD / "AppIcon.iconset"),
    "-o", str(CONTENTS / "Resources/AppIcon.icns"))
run("plutil", "-lint", str(CONTENTS / "Info.plist"))
run("codesign", "--force", "--sign", "-", str(APP))
run("codesign", "--verify", "--strict", "--verbose=2", str(APP))
print(f"Built: {APP}")
