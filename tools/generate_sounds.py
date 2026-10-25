#!/usr/bin/env python3
"""Generate the game's small procedural sound effects with the stdlib only.

The WAV files are build products, not Git-tracked binaries. Run this before
opening/importing the Godot project locally; CI runs it before Godot import and
APK export. Fixed random seeds make repeated builds reproducible.
"""

import math
from pathlib import Path
import random
import struct
import wave

SAMPLE_RATE = 44_100
CHANNELS = 1
SAMPLE_WIDTH = 2  # signed 16-bit PCM
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sounds"


def _pcm16(value: float) -> int:
    """Clamp a normalized float sample and convert it to signed 16-bit PCM."""
    return int(round(max(-1.0, min(1.0, value)) * 32_767))


def _write_wav(path: Path, samples: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = struct.pack("<" + "h" * len(samples), *samples)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(CHANNELS)
        output.setsampwidth(SAMPLE_WIDTH)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm)

    # Fail CI immediately if the generated resource is not a readable PCM WAV.
    with wave.open(str(path), "rb") as check:
        assert check.getnchannels() == CHANNELS
        assert check.getsampwidth() == SAMPLE_WIDTH
        assert check.getframerate() == SAMPLE_RATE
        assert check.getnframes() == len(samples)
    print(f"Generated {path.relative_to(OUTPUT_DIR.parent.parent)}: "
          f"{len(samples)} frames, {path.stat().st_size} bytes")


def make_shoot() -> list[int]:
    """0.15 s punchy noise crack with exponential decay and a low body thump."""
    duration = 0.15
    rng = random.Random(0x5107)  # deterministic white noise
    samples = []
    for index in range(int(SAMPLE_RATE * duration)):
        t = index / SAMPLE_RATE
        envelope = math.exp(-36.0 * t)
        noise = rng.uniform(-1.0, 1.0)
        body = math.sin(2.0 * math.pi * 85.0 * t)
        samples.append(_pcm16((0.88 * noise + 0.24 * body) * envelope))
    return samples


def make_footstep() -> list[int]:
    """0.1 s heavy 100 Hz thud with a small deterministic noise component."""
    duration = 0.10
    rng = random.Random(0xF007)
    samples = []
    for index in range(int(SAMPLE_RATE * duration)):
        t = index / SAMPLE_RATE
        attack = min(1.0, t / 0.003)
        release = min(1.0, (duration - t) / 0.020)
        envelope = math.exp(-24.0 * t) * attack * release
        thud = math.sin(2.0 * math.pi * 100.0 * t)
        noise = rng.uniform(-1.0, 1.0)
        samples.append(_pcm16((0.84 * thud + 0.14 * noise) * envelope))
    return samples


def main() -> None:
    _write_wav(OUTPUT_DIR / "shoot.wav", make_shoot())
    _write_wav(OUTPUT_DIR / "footstep.wav", make_footstep())


if __name__ == "__main__":
    main()
