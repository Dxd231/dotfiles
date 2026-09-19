#!/usr/bin/env python3
"""
Live BPM / beat detector.

Captures audio output (preferring per-application direct capture via PipeWire/JACK,
or falling back to the system output monitor via PulseAudio/PipeWire) and runs
aubio's tempo tracker on it in real time. Emits one JSON line per detected beat
on stdout:

    {"bpm": 128.4, "beat": true, "ts": 1758271234.12}

Meant to be spawned as a subprocess (e.g. from Quickshell Process) and have its
stdout parsed line by line.
"""

import json
import os
import signal
import statistics
import sys
import time
from collections import deque

import numpy as np
import sounddevice as sd
import aubio

# Target application from command line or environment
TARGET_APP = (
    sys.argv[1].strip()
    if len(sys.argv) > 1 and sys.argv[1].strip()
    else os.environ.get("BPM_SOURCE_APP", "spotify")
)

WIN_S = 1024  # analysis window
HOP_S = 512   # samples per callback (10.67ms @ 48kHz)


class BpmFilter:
    """Rolling median filter with octave fold sanity check."""
    def __init__(self, window_size=5, min_bpm=50.0, max_bpm=210.0):
        self.history = deque(maxlen=window_size)
        self.min_bpm = min_bpm
        self.max_bpm = max_bpm

    def add(self, raw_bpm):
        if raw_bpm <= 0 or not np.isfinite(raw_bpm):
            return None
        bpm = float(raw_bpm)
        # Fold into plausible tempo range if extreme octave error
        while bpm > self.max_bpm and (bpm / 2.0) >= self.min_bpm:
            bpm /= 2.0
        while bpm < self.min_bpm and (bpm * 2.0) <= self.max_bpm:
            bpm *= 2.0

        self.history.append(bpm)
        return statistics.median(self.history)


def find_source_device(target_app):
    """
    Find best audio capture device:
    1. Direct per-application capture (PipeWire/JACK bridge client matching target_app).
    2. Fallback to Pulse/PipeWire-Pulse monitor (system loopback).
    3. Fallback to any device matching 'monitor'.
    4. Fallback to 'pulse', 'pipewire', or 'default' device.
    """
    try:
        devices = sd.query_devices()
    except Exception as e:
        print(f"Error querying audio devices: {e}", file=sys.stderr)
        return None, None

    # 1. Direct per-application client (e.g. 'Spotify/spotify', 'LibreWolf', 'mpv')
    if target_app:
        target_lower = target_app.lower()
        for idx, dev in enumerate(devices):
            if dev["max_input_channels"] > 0 and target_lower in dev["name"].lower():
                return idx, dev

    # Ensure PULSE_SOURCE is set to system monitor for PortAudio's pulse device
    os.environ.setdefault("PULSE_SOURCE", "@DEFAULT_MONITOR@")

    # 2. PortAudio's 'pulse' device (with PULSE_SOURCE=@DEFAULT_MONITOR@)
    for idx, dev in enumerate(devices):
        if dev["max_input_channels"] > 0 and dev["name"].lower() == "pulse":
            return idx, dev

    # 3. Any device with 'monitor' in the name
    for idx, dev in enumerate(devices):
        if dev["max_input_channels"] > 0 and "monitor" in dev["name"].lower():
            return idx, dev

    # 4. Fallback to default or pipewire device
    for idx, dev in enumerate(devices):
        if dev["max_input_channels"] > 0 and dev["name"].lower() in ("default", "pipewire"):
            return idx, dev

    # 5. Any available input device
    for idx, dev in enumerate(devices):
        if dev["max_input_channels"] > 0:
            return idx, dev

    return None, None


def main():
    # Graceful exit on signal
    def handle_sig(sig, frame):
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sig)
    signal.signal(signal.SIGTERM, handle_sig)

    # Ensure unbuffered line-by-line output
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)

    target_app = TARGET_APP

    bpm_filter = BpmFilter(window_size=5)

    while True:
        device_idx, device_info = find_source_device(target_app)
        if device_idx is None:
            print(
                f"No audio capture device found for '{target_app}', retrying...",
                file=sys.stderr,
                flush=True,
            )
            time.sleep(1)
            continue

        samplerate = int(device_info.get("default_samplerate") or 48000)
        channels = min(2, device_info["max_input_channels"])

        # 'specdiff' (spectral difference) is stable and robust against transient noise
        tempo_detector = aubio.tempo("specdiff", WIN_S, HOP_S, samplerate)
        tempo_detector.set_silence(-42)
        tempo_detector.set_threshold(0.3)

        def callback(indata, frames, time_info, status):
            if status:
                print(f"stream status: {status}", file=sys.stderr, flush=True)

            mono = (
                np.mean(indata, axis=1).astype(np.float32)
                if channels > 1
                else indata[:, 0].astype(np.float32)
            )

            # Skip processing on silence
            rms = np.sqrt(np.mean(mono**2))
            if rms < 0.0005:
                return

            is_beat = tempo_detector(mono)
            if is_beat[0]:
                raw_bpm = tempo_detector.get_bpm()
                bpm = bpm_filter.add(raw_bpm)
                if bpm and bpm > 0:
                    print(
                        json.dumps(
                            {"bpm": round(float(bpm), 1), "beat": True, "ts": time.time()}
                        ),
                        flush=True,
                    )

        try:
            print(
                f"listening on: {device_info['name']} (target: '{target_app}')",
                file=sys.stderr,
                flush=True,
            )
            with sd.InputStream(
                device=device_idx,
                channels=channels,
                samplerate=samplerate,
                blocksize=HOP_S,
                dtype="float32",
                callback=callback,
            ):
                while True:
                    time.sleep(1)
        except Exception as e:
            print(f"Audio stream error: {e}, reconnecting...", file=sys.stderr, flush=True)
            time.sleep(1)


if __name__ == "__main__":
    main()
