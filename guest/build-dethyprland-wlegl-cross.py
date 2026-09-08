#!/usr/bin/env python3
"""Incrementally cross-link android_wlegl against a captured, pinned guest build.

Requires build/dethyprland-sysroot with guest headers/libraries/build-det and
build/dethyprland-src/Hyprland with the android_wlegl patch applied. Does not
install artifacts or start the guest. The cached objects are from the existing
compositor; this is not a clean-source release build.
"""
import json
from pathlib import Path
import shlex
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SYSROOT = ROOT / "build/dethyprland-sysroot"
SOURCE = ROOT / "build/dethyprland-src/Hyprland"
CACHE = SYSROOT / "root/build/dethyprland/Hyprland/build-det"
OUTPUT = ROOT / "build/dethyprland-wlegl-cross"
IMAGE = "determination/quickshell-cross:trixie"
PIN = "9958d297641b5c84dcff93f9039d80a5ad37ab00"


def container_path(path):
    return "/work/" + str(Path(path).relative_to(ROOT))


def target_path(path):
    if path.startswith("/root/build/dethyprland/Hyprland/"):
        return container_path(SOURCE) + path.removeprefix("/root/build/dethyprland/Hyprland")
    if path.startswith(("/usr/", "/opt/")):
        return container_path(SYSROOT) + path
    return path


def run(args, cwd=ROOT):
    subprocess.run(["podman", "run", "--rm", "-v", f"{ROOT}:/work", "-w",
                    container_path(cwd), IMAGE, *args], check=True)


def main():
    revision = subprocess.check_output(["git", "-C", str(SOURCE), "rev-parse", "HEAD"], text=True).strip()
    if revision != PIN:
        raise SystemExit("Unexpected Hyprland revision")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    adapter = SOURCE / "src/dethyprland"
    adapter.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "graphics/dethyprland/AndroidWlegl.cpp", adapter / "AndroidWlegl.cpp")
    entries = json.loads((CACHE / "compile_commands.json").read_text())
    template = next(e for e in entries if e["file"].endswith("/src/render/Texture.cpp"))
    tokens = shlex.split(template["command"])
    flags = ["--sysroot=" + container_path(SYSROOT), "-std=c++23"]
    i = 1
    while i < len(tokens):
        token = tokens[i]
        if token in ("-o", "-c", "-Xclang"):
            i += 2
            continue
        if token.startswith(("@", "-std=", "-fmacro-prefix-map=")) or token == "-Winvalid-pch":
            i += 1
            continue
        if token.startswith("-I/"):
            token = "-I" + target_path(token[2:])
        elif token.startswith("/"):
            token = target_path(token)
        flags.append(token)
        i += 1
    protocols = SYSROOT / "root/build/dethyprland/Hyprland/protocols"
    flags += ["-I" + container_path(protocols), "-I" + container_path(OUTPUT),
              "-I" + container_path(SYSROOT / "usr/include/android")]
    xml = ROOT / "graphics/dethyprland/wayland-android.xml"
    for mode, name in (("server-header", "wayland-android-protocol.h"),
                       ("private-code", "wayland-android-protocol.c")):
        run(["wayland-scanner", mode, container_path(xml), container_path(OUTPUT / name)])
    objects = {}
    for source in ("src/render/Texture.cpp", "src/managers/ProtocolManager.cpp", "src/dethyprland/AndroidWlegl.cpp"):
        obj = OUTPUT / (Path(source).stem + ".o")
        run(["aarch64-linux-gnu-g++", *flags, "-c", container_path(SOURCE / source), "-o", container_path(obj)])
        objects[f"CMakeFiles/Hyprland.dir/{source}.o"] = container_path(obj)
    protocol_obj = container_path(OUTPUT / "wayland-android-protocol.o")
    run(["aarch64-linux-gnu-gcc", "--sysroot=" + container_path(SYSROOT), "-c",
         container_path(OUTPUT / "wayland-android-protocol.c"), "-o", protocol_obj])
    commands = subprocess.check_output(["ninja", "-C", str(CACHE), "-t", "commands", "Hyprland"], text=True)
    link = shlex.split(commands.splitlines()[-1])
    if link[:2] != [":", "&&"] or link[-2:] != ["&&", ":"]:
        raise SystemExit("Unexpected cached link command")
    link = link[3:-2]
    rewritten = []
    for token in link:
        if token == "Hyprland":
            token = container_path(OUTPUT / "Hyprland")
        elif token.startswith("-Wl,-rpath,"):
            token = token.rstrip(":")
        else:
            token = objects.get(token, target_path(token))
        rewritten.append(token)
    run(["aarch64-linux-gnu-g++", "--sysroot=" + container_path(SYSROOT),
         "-Wl,-rpath-link," + container_path(SYSROOT / "usr/local/lib"),
         "-Wl,-rpath-link," + container_path(SYSROOT / "opt/dethyprland/lib"),
         "-Wl,-rpath-link," + container_path(SYSROOT / "usr/lib/aarch64-linux-gnu"),
         objects["CMakeFiles/Hyprland.dir/src/dethyprland/AndroidWlegl.cpp.o"], protocol_obj,
         *rewritten, container_path(SYSROOT / "usr/local/lib/libgralloc.so"),
         container_path(SYSROOT / "usr/local/lib/libhybris-common.so")], cwd=CACHE)
    print(OUTPUT / "Hyprland")


if __name__ == "__main__":
    main()
