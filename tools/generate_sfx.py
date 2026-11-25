#!/usr/bin/env python3
"""Genera los efectos de sonido provisionales del prototipo (síntesis, sin dependencias).

Uso:  python3 tools/generate_sfx.py
Crea audio/sfx/*.wav (mono, 16 bits, 44.1 kHz). Cambia los parámetros y vuelve a ejecutarlo;
Godot reimporta los .wav solos. Son sonidos de prototipo: sustitúyelos por otros cuando quieras
manteniendo el mismo nombre de archivo.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "sfx")


# --- Primitivas -------------------------------------------------------------------

def silence(seconds):
    return [0.0] * int(seconds * RATE)


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * RATE))]


def tone(seconds, f0, f1=None, shape="sine", vibrato=0.0, vib_rate=6.0):
    """Tono con barrido de frecuencia f0 -> f1 (exponencial)."""
    f1 = f0 if f1 is None else f1
    n = int(seconds * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / max(n - 1, 1)
        f = f0 * (f1 / f0) ** t
        f *= 1.0 + vibrato * math.sin(2 * math.pi * vib_rate * i / RATE)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            out.append(math.sin(phase))
        elif shape == "tri":
            out.append(2 / math.pi * math.asin(math.sin(phase)))
        else:  # saw suave
            out.append(((phase / math.pi) % 2.0) - 1.0)
    return out


def lowpass(x, cutoff):
    """Pasa bajos de un polo. cutoff puede ser número o función t(0-1) -> Hz."""
    out, y, n = [], 0.0, len(x)
    for i, v in enumerate(x):
        c = cutoff(i / max(n - 1, 1)) if callable(cutoff) else cutoff
        a = 1.0 - math.exp(-2 * math.pi * c / RATE)
        y += a * (v - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    low = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, low)]


def bandpass(x, low, high):
    return lowpass(highpass(x, low), high)


def env_decay(x, attack=0.002, decay=0.1):
    """Ataque lineal y caída exponencial (decay = segundos hasta ~37 %)."""
    out = []
    for i, v in enumerate(x):
        t = i / RATE
        g = t / attack if t < attack else math.exp(-(t - attack) / decay)
        out.append(v * g)
    return out


def env_swell(x, peak=0.5):
    """Sube y baja (forma de campana); peak = posición relativa del máximo."""
    n = len(x)
    out = []
    for i, v in enumerate(x):
        t = i / max(n - 1, 1)
        g = math.sin(math.pi * min(t / peak, 1.0) / 2) if t < peak else math.cos(math.pi / 2 * (t - peak) / (1 - peak))
        out.append(v * g)
    return out


def gain(x, g):
    return [v * g for v in x]


def mix(*tracks):
    """Mezcla pistas (lista de (offset_segundos, muestras))."""
    length = max(int(off * RATE) + len(s) for off, s in tracks)
    out = [0.0] * length
    for off, s in tracks:
        start = int(off * RATE)
        for i, v in enumerate(s):
            out[start + i] += v
    return out


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def fade_out(x, seconds=0.01):
    n = min(len(x), int(seconds * RATE))
    for i in range(n):
        x[len(x) - n + i] *= 1.0 - i / n
    return x


def save(name, x, peak=0.85):
    x = fade_out(list(x))
    m = max(1e-9, max(abs(v) for v in x))
    x = [v / m * peak for v in x]
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in x))
    print(f"  {name}.wav  {len(x) / RATE:.2f} s")


# --- Sonidos ----------------------------------------------------------------------

def footstep(rng):
    thud = env_decay(lowpass(noise(0.12, rng), 420 * rng.uniform(0.85, 1.15)), 0.002, 0.025)
    body = env_decay(tone(0.1, 160 * rng.uniform(0.9, 1.1), 110, shape="tri"), 0.001, 0.025)
    scuff = env_decay(bandpass(noise(0.08, rng), 1500, 4000), 0.004, 0.012)
    return mix((0, gain(thud, 1.0)), (0, gain(body, 0.6)), (0.005, gain(scuff, 0.3)))


def slide(seconds, rng, rising=True):
    """Puerta corredera: roce filtrado que crece y cae."""
    sweep = (lambda t: 500 + 900 * t) if rising else (lambda t: 1400 - 900 * t)
    return env_swell(lowpass(highpass(noise(seconds, rng), 150), sweep), 0.4)


def thunk(rng, freq=70, decay=0.08, bright=0.3):
    low = env_decay(tone(0.35, freq * 1.3, freq), 0.001, decay)
    knock = env_decay(lowpass(noise(0.2, rng), 900), 0.001, decay * 0.4)
    return mix((0, low), (0, gain(knock, bright)))


def creak(seconds, rng, f0=280, f1=420):
    raw = tone(seconds, f0, f1, shape="saw", vibrato=0.08, vib_rate=23)
    grit = [v * (0.6 + 0.4 * rng.random()) for v in raw]
    return env_swell(bandpass(grit, 300, 1800), 0.3)


def click(rng, freq=3000):
    return env_decay(bandpass(noise(0.03, rng), freq * 0.5, freq * 1.5), 0.0005, 0.004)


def whoosh(seconds, rng, f_from=400, f_to=2500):
    return env_swell(lowpass(highpass(noise(seconds, rng), 200), lambda t: f_from + (f_to - f_from) * math.sin(math.pi * t)), 0.45)


def heartbeat_beat(rng):
    low = env_decay(lowpass(tone(0.25, 62, 48), 200), 0.004, 0.06)
    mid = env_decay(tone(0.15, 200, 140, shape="tri"), 0.003, 0.035)
    return mix((0, gain(low, 0.35)), (0, mid))


def chord(freqs, seconds, shape="tri", decay=0.5):
    voices = [env_decay(tone(seconds, f, shape=shape), 0.01, decay) for f in freqs]
    return mix(*[(0, v) for v in voices])


def arpeggio(freqs, step, seconds, shape="tri", decay=0.35):
    return mix(*[(i * step, env_decay(tone(seconds, f, shape=shape), 0.005, decay)) for i, f in enumerate(freqs)])


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(7)
    print("Generando efectos en", os.path.abspath(OUT))

    for i in range(4):
        save(f"step_{i}", footstep(rng), peak=0.7)

    save("door_open", mix((0, slide(0.45, rng, True)), (0.42, gain(thunk(rng, 90, 0.05, 0.4), 0.5))))
    save("door_close", mix((0, slide(0.4, rng, False)), (0.38, thunk(rng, 70, 0.09, 0.6))))
    save("switch", mix((0, click(rng, 3500)), (0.035, gain(click(rng, 2200), 0.7))), peak=0.6)

    save("wardrobe_enter", mix((0, gain(creak(0.35, rng, 260, 380), 0.6)), (0.32, thunk(rng, 85, 0.07, 0.8))))
    save("wardrobe_exit", mix((0, gain(thunk(rng, 95, 0.05, 0.6), 0.7)), (0.05, gain(creak(0.4, rng, 400, 250), 0.6))))
    rummage = []
    for k in range(9):
        rummage.append((k * 0.11 + rng.uniform(0, 0.04), gain(env_decay(bandpass(noise(0.12, rng), 600, rng.uniform(2000, 5000)), 0.005, 0.03), rng.uniform(0.4, 1.0))))
    save("wardrobe_search", mix(*rummage), peak=0.7)
    save("wardrobe_found", mix((0, thunk(rng, 60, 0.12, 0.8)), (0.05, gain(tone(0.5, 330, 660, shape="tri"), 0.0)), (0.05, env_decay(tone(0.6, 220, 440, shape="saw"), 0.01, 0.2))))

    save("net_fire", mix((0, whoosh(0.32, rng, 500, 3000)), (0, gain(click(rng, 1800), 0.5))))
    save("net_hit", mix((0, thunk(rng, 110, 0.05, 0.9)), (0.02, gain(env_decay(bandpass(noise(0.4, rng), 800, 3500), 0.01, 0.1), 0.6))))
    save("net_miss", gain(thunk(rng, 140, 0.03, 1.0), 0.6), peak=0.5)
    save("net_escape", mix((0, env_decay(bandpass(noise(0.35, rng), 1500, 6000), 0.002, 0.06)), (0.02, env_decay(tone(0.4, 300, 900, shape="tri"), 0.01, 0.15))))
    save("capture", mix((0, env_decay(tone(0.9, 700, 180, shape="sine", vibrato=0.04, vib_rate=7), 0.01, 0.35)),
                        (0.0, gain(env_decay(tone(0.9, 1050, 270, shape="sine", vibrato=0.04, vib_rate=7), 0.01, 0.3), 0.4))))

    save("heartbeat", mix((0, heartbeat_beat(rng)), (0.18, gain(heartbeat_beat(rng), 0.7)), (0.0, silence(0.75))), peak=0.8)

    save("beep", env_decay(tone(0.15, 880), 0.003, 0.05), peak=0.5)
    save("hunt_start", arpeggio([440, 554, 659, 880], 0.07, 0.4, "tri", 0.18), peak=0.7)
    save("win", arpeggio([523, 659, 784, 1047], 0.12, 0.9, "tri", 0.4), peak=0.7)
    save("lose", arpeggio([392, 311, 262, 196], 0.16, 1.0, "tri", 0.45), peak=0.7)
    save("ui_click", click(rng, 2500), peak=0.4)

    # Pulso de la Presa cuando el Cazador está en su habitación: latido fuerte (lub-dub).
    # Los altavoces de móvil no reproducen graves por debajo de ~150 Hz: el golpe lleva armónicos
    # medios (150-400 Hz) y un "toc" agudo para que se oiga; el grave queda para auriculares.
    def pulse_beat(strength):
        sub = env_decay(tone(0.3, 60, 42), 0.003, 0.07)
        mid = env_decay(tone(0.18, 190, 130, shape="tri"), 0.002, 0.035)
        harm = env_decay(tone(0.12, 380, 260), 0.001, 0.02)
        knock = env_decay(bandpass(noise(0.05, rng), 600, 2200), 0.0008, 0.008)
        return gain(mix((0, gain(sub, 0.3)), (0, mid), (0, gain(harm, 0.7)), (0, gain(knock, 0.4))), strength)
    save("pulse", mix((0, pulse_beat(1.0)), (0.17, pulse_beat(0.8)), (0, silence(0.5))), peak=0.98)


if __name__ == "__main__":
    main()
