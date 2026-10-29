#!/usr/bin/env python3
"""Assembles the website (also bundled into the Android app) into build/web.

    python3 tools/build_web.py [output_dir]

It copies web/ and adds the files the iPhone app also uses: levels.json, the
community server settings (backend.json), the sound effects and the icon.
"""
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "web"))
RES = os.path.join(ROOT, "Thrustbound", "Resources")
ICON = os.path.join(ROOT, "Thrustbound", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT)
web = os.path.join(ROOT, "web")
for name in ("index.html", "manifest.webmanifest"):
    shutil.copy(os.path.join(web, name), OUT)
for folder in ("css", "js"):
    shutil.copytree(os.path.join(web, folder), os.path.join(OUT, folder))
shutil.copy(os.path.join(RES, "levels.json"), OUT)
if os.path.exists(os.path.join(RES, "backend.json")):
    shutil.copy(os.path.join(RES, "backend.json"), OUT)
shutil.copytree(os.path.join(RES, "Sounds"), os.path.join(OUT, "sounds"))

try:
    from PIL import Image
    icon = Image.open(ICON).convert("RGB")
    for size in (180, 192, 512):
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"icon-{size}.png"), optimize=True)
except ImportError:
    for size in (180, 192, 512):
        shutil.copy(ICON, os.path.join(OUT, f"icon-{size}.png"))

project = open(os.path.join(ROOT, "project.yml")).read()
version = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', project).group(1)
build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', project).group(1)
json.dump({"version": f"{version} ({build})"}, open(os.path.join(OUT, "build-info.json"), "w"))
open(os.path.join(OUT, ".nojekyll"), "w").close()

total = sum(os.path.getsize(os.path.join(d, f)) for d, _, files in os.walk(OUT) for f in files)
print(f"web build: {OUT} ({total / 1024:.0f} KB, version {version} ({build}))")
