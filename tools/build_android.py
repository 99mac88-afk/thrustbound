#!/usr/bin/env python3
"""Prepares the Android project: copies the website into the APK's assets and
makes the launcher icons. Then build with Gradle:

    python3 tools/build_android.py
    cd android && gradle assembleRelease      # -> app/build/outputs/apk/release/app-release.apk
"""
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "android", "app", "src", "main")
ICON = os.path.join(ROOT, "Thrustbound", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

subprocess.check_call([sys.executable, os.path.join(ROOT, "tools", "build_web.py"), os.path.join(APP, "assets", "www")])
# GitHub Pages marker; not needed inside the app.
os.remove(os.path.join(APP, "assets", "www", ".nojekyll"))

res = os.path.join(APP, "res")
for d in os.listdir(res):
    if d.startswith("mipmap-"):
        shutil.rmtree(os.path.join(res, d))
icon = Image.open(ICON).convert("RGB")
for name, scale in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
    folder = os.path.join(res, f"mipmap-{name}")
    os.makedirs(folder)
    icon.resize((round(48 * scale),) * 2, Image.LANCZOS).save(os.path.join(folder, "ic_launcher.png"))
    # Adaptive icon layer (108 dp); the launcher masks it to its own shape.
    icon.resize((round(108 * scale),) * 2, Image.LANCZOS).save(os.path.join(folder, "ic_launcher_foreground.png"))
os.makedirs(os.path.join(res, "mipmap-anydpi-v26"))
with open(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/space" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '</adaptive-icon>\n')
print("android project ready:", os.path.join(ROOT, "android"))
