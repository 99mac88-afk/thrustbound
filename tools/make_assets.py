#!/usr/bin/env python3
"""
Generates Thrustbound's app icon and sound effects.

  python3 tools/make_assets.py

Writes:
  Thrustbound/Assets.xcassets/AppIcon.appiconset/AppIcon.png  (1024x1024, opaque)
  Thrustbound/Resources/Sounds/*.wav                          (44.1 kHz mono)
"""

import math
import os
import random
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "Thrustbound", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
SOUNDS = os.path.join(ROOT, "Thrustbound", "Resources", "Sounds")
RATE = 44100


# ------------------------------------------------------------------ icon
def quad(p0, c, p1, n=16):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t ** 2 * p1[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t ** 2 * p1[1]
        pts.append((x, y))
    return pts


def rocket_parts():
    """Same shapes as RocketArt in the app (rocket space, y up)."""
    hull = quad((0, 20), (8, 14), (8, 4)) + [(8, -12), (-8, -12), (-8, 4)] + quad((-8, 4), (-8, 14), (0, 20))
    nose = quad((0, 20), (6.2, 16), (6.6, 10)) + [(-6.6, 10)] + quad((-6.6, 10), (-6.2, 16), (0, 20))
    fin_l = [(-8, -1), (-13, -12), (-13, -20), (-10, -20), (-8, -13)]
    fin_r = [(x * -1, y) for (x, y) in fin_l]
    stripe = [(-8, -9), (8, -9), (8, -6), (-8, -6)]
    nozzle = [(-5, -12), (5, -12), (6.5, -16), (-6.5, -16)]
    flame_o = quad((-5, -15), (-5, -15 - 13), (0, -15 - 26)) + quad((0, -15 - 26), (5, -15 - 13), (5, -15))
    flame_i = quad((-3, -15), (-3, -15 - 8), (0, -15 - 15)) + quad((0, -15 - 15), (3, -15 - 8), (3, -15))
    return hull, nose, fin_l, fin_r, stripe, nozzle, flame_o, flame_i


def make_icon():
    S = 2048
    img = Image.new("RGB", (S, S))
    px = np.zeros((S, S, 3), dtype=np.float32)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    top = np.array([6, 10, 32], dtype=np.float32)
    bottom = np.array([34, 16, 80], dtype=np.float32)
    t = np.clip((xx * 0.35 + yy * 0.65), 0, 1)[..., None]
    px[:] = top * (1 - t) + bottom * t
    # cyan glow behind the rocket
    d = np.sqrt((xx - 0.55) ** 2 + (yy - 0.42) ** 2)
    glow = np.exp(-(d / 0.28) ** 2)[..., None]
    px += glow * np.array([30, 140, 190], dtype=np.float32) * 0.55
    img = Image.fromarray(np.clip(px, 0, 255).astype(np.uint8))

    draw = ImageDraw.Draw(img)
    rng = random.Random(11)
    for _ in range(170):
        x, y = rng.uniform(0, S), rng.uniform(0, S * 0.8)
        r = rng.choice([2, 3, 3, 4, 6])
        a = rng.randint(120, 255)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(a, a, min(255, a + 20)))

    # planet horizon with neon rim
    planet = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pd = ImageDraw.Draw(planet)
    cx, cy, R = S * 0.5, S * 1.55, S * 0.82
    pd.ellipse([cx - R - 30, cy - R - 30, cx + R + 30, cy + R + 30], fill=(59, 227, 255, 90))
    pd.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(14, 34, 64, 255))
    planet = planet.filter(ImageFilter.GaussianBlur(2))
    img.paste(planet, (0, 0), planet)
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(110, 240, 255, 255), width=14)
    rim_glow = rim.filter(ImageFilter.GaussianBlur(18))
    img.paste(rim_glow, (0, 0), rim_glow)
    img.paste(rim, (0, 0), rim)

    # landing pad on the horizon
    pad_x = S * 0.72
    pad_w, pad_y = S * 0.16, cy - math.sqrt(R * R - (pad_x - cx) ** 2)
    pad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    padd = ImageDraw.Draw(pad)
    padd.rectangle([pad_x - pad_w / 2, pad_y - 26, pad_x + pad_w / 2, pad_y + 6], fill=(68, 255, 136, 255))
    pad_glow = pad.filter(ImageFilter.GaussianBlur(26))
    img.paste(pad_glow, (0, 0), pad_glow)
    img.paste(pad, (0, 0), pad)

    # rocket
    hull, nose, fin_l, fin_r, stripe, nozzle, flame_o, flame_i = rocket_parts()
    scale = S / 88
    angle = math.radians(-30)
    ox, oy = S * 0.5, S * 0.4

    def tr(points):
        out = []
        for (x, y) in points:
            rx = x * math.cos(angle) - y * math.sin(angle)
            ry = x * math.sin(angle) + y * math.cos(angle)
            out.append((ox + rx * scale, oy - ry * scale))
        return out

    fl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fl)
    fd.polygon(tr([(x * 1.25, (y + 15) * 1.25 - 15) for (x, y) in flame_o]), fill=(255, 122, 46, 255))
    fl_glow = fl.filter(ImageFilter.GaussianBlur(60))
    img.paste(fl_glow, (0, 0), fl_glow)
    img.paste(fl, (0, 0), fl)
    d2 = ImageDraw.Draw(img)
    d2.polygon(tr([(x * 1.2, (y + 15) * 1.2 - 15) for (x, y) in flame_i]), fill=(255, 244, 176))

    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    red = (255, 77, 94, 255)
    bd.polygon(tr(fin_l), fill=red)
    bd.polygon(tr(fin_r), fill=red)
    bd.polygon(tr(nozzle), fill=(59, 70, 89, 255))
    bd.polygon(tr(hull), fill=(238, 243, 251, 255), outline=(157, 176, 201, 255))
    bd.polygon(tr(stripe), fill=red)
    bd.polygon(tr(nose), fill=red)
    wc = tr([(0, 3)])[0]
    wr = 3.6 * scale
    bd.ellipse([wc[0] - wr - 10, wc[1] - wr - 10, wc[0] + wr + 10, wc[1] + wr + 10], fill=(255, 255, 255, 255))
    bd.ellipse([wc[0] - wr, wc[1] - wr, wc[0] + wr, wc[1] + wr], fill=(111, 216, 255, 255))
    bd.ellipse([wc[0] - wr * 0.5, wc[1] - wr * 0.6, wc[0] - wr * 0.05, wc[1] - wr * 0.15], fill=(220, 248, 255, 255))
    shadow = body.filter(ImageFilter.GaussianBlur(30))
    shadow_rgba = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_rgba.paste((0, 20, 40, 160), (0, 0), shadow)
    img.paste(shadow_rgba, (24, 30), shadow_rgba)
    img.paste(body, (0, 0), body)

    img = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
    os.makedirs(os.path.dirname(ICON), exist_ok=True)
    img.save(ICON)
    print("wrote", ICON)


# ------------------------------------------------------------------ sound
def save(name, samples):
    samples = np.asarray(samples, dtype=np.float64)
    peak = np.max(np.abs(samples)) or 1.0
    samples = samples / peak * 0.89
    data = (samples * 32767).astype(np.int16)
    os.makedirs(SOUNDS, exist_ok=True)
    path = os.path.join(SOUNDS, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("wrote", path, f"{len(data) / RATE:.2f}s")


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def env(t, attack, decay):
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay)


def lowpass(x, cutoff):
    alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def bell(freq, t, decay=0.35):
    return (np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2.01 * t)
            + 0.15 * np.sin(2 * np.pi * freq * 3.02 * t)) * np.exp(-t / decay)


def note_at(freq, start, length, total, decay=0.3, wave_fn=None):
    t = t_axis(total)
    out = np.zeros_like(t)
    m = (t >= start) & (t < start + length)
    tt = t[m] - start
    tone = bell(freq, tt, decay) if wave_fn is None else wave_fn(freq, tt) * np.exp(-tt / decay)
    out[m] = tone * np.clip(tt / 0.005, 0, 1)
    return out


def make_sounds():
    rng = np.random.default_rng(5)

    # engine loop: low rumbling noise that loops seamlessly
    dur = 1.6
    n = int(RATE * dur)
    noise = rng.standard_normal(n + RATE // 4)
    rumble = lowpass(noise, 420) + 0.5 * lowpass(noise, 1400) * 0.4
    t = np.arange(len(rumble)) / RATE
    rumble *= 0.85 + 0.15 * np.sin(2 * np.pi * 9 * t)
    fade = RATE // 4
    body = rumble[:n].copy()
    tail = rumble[n:n + fade]
    ramp = np.linspace(0, 1, fade)
    body[:fade] = body[:fade] * ramp + tail * (1 - ramp)
    save("thrust", body)

    # star pickup: bright rising arpeggio
    total = 0.55
    s = note_at(1318.5, 0.0, 0.5, total, 0.18) + note_at(1661.2, 0.06, 0.5, total, 0.18) \
        + note_at(1975.5, 0.12, 0.45, total, 0.25) * 0.9
    save("star", s)

    # fuel can: bubbly upward sweep
    t = t_axis(0.32)
    f = 320 + 900 * (t / 0.32) ** 1.4
    phase = 2 * np.pi * np.cumsum(f) / RATE
    save("fuel", np.sin(phase) * env(t, 0.005, 0.12) + 0.3 * np.sin(2 * phase) * env(t, 0.005, 0.08))

    # key: two-tone chime
    total = 0.8
    save("key", note_at(880, 0, 0.8, total, 0.35) + note_at(1318.5, 0.12, 0.7, total, 0.4))

    # door: mechanical whoosh + clunk
    t = t_axis(0.6)
    sweep = lowpass(rng.standard_normal(len(t)), 900) * env(t, 0.08, 0.18)
    clunk = np.sin(2 * np.pi * 70 * t) * env(t, 0.002, 0.08)
    shimmer = note_at(660, 0.05, 0.5, 0.6, 0.25) * 0.4
    save("door", sweep * 1.2 + clunk * 0.8 + shimmer)

    # crash: explosion
    t = t_axis(1.4)
    burst = rng.standard_normal(len(t))
    boom = lowpass(burst, 700) * env(t, 0.003, 0.35) * 1.6 + lowpass(burst, 3000) * env(t, 0.001, 0.08) * 0.6
    thump = np.sin(2 * np.pi * (55 + 30 * np.exp(-t * 8)) * t) * env(t, 0.002, 0.3)
    save("crash", boom + thump * 1.2)

    # landing jingle
    total = 1.3
    tri = lambda fr, tt: 2 / np.pi * np.arcsin(np.sin(2 * np.pi * fr * tt))
    j = note_at(523.3, 0.00, 0.5, total, 0.25, tri) + note_at(659.3, 0.10, 0.5, total, 0.25, tri) \
        + note_at(784.0, 0.20, 0.5, total, 0.3, tri) + note_at(1046.5, 0.32, 1.0, total, 0.45, tri) \
        + note_at(1318.5, 0.32, 1.0, total, 0.45) * 0.35
    save("land", j)

    # UI click
    t = t_axis(0.05)
    save("click", np.sin(2 * np.pi * 1900 * t) * env(t, 0.0005, 0.008) + 0.3 * rng.standard_normal(len(t)) * env(t, 0.0002, 0.003))

    # bump
    t = t_axis(0.2)
    save("bump", np.sin(2 * np.pi * (95 + 40 * np.exp(-t * 30)) * t) * env(t, 0.001, 0.05)
         + lowpass(rng.standard_normal(len(t)), 1200) * env(t, 0.001, 0.02) * 0.6)

    # low fuel warning: two short beeps
    total = 0.36
    sq = lambda fr, tt: np.sign(np.sin(2 * np.pi * fr * tt)) * 0.5 + 0.5 * np.sin(2 * np.pi * fr * tt)
    b1 = note_at(880, 0.0, 0.12, total, 0.5, sq)
    b2 = note_at(880, 0.18, 0.12, total, 0.5, sq)
    save("lowfuel", (b1 + b2) * 0.8)


if __name__ == "__main__":
    make_icon()
    make_sounds()
