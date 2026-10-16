#!/usr/bin/env python3
"""Make a short synthetic 4-source track with known stems, for an SDR check of the separation.
Writes <dir>/mix.wav and <dir>/{drums,bass,vocals,other}.wav (44.1 kHz stereo 16-bit).
The sources are crude on purpose: the point is a ground truth, not realism."""
import sys, os, numpy as np, soundfile as sf
out = sys.argv[1]; secs = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
os.makedirs(out, exist_ok=True)
sr = 44100; n = int(sr * secs); t = np.arange(n) / sr; bpm = 110.0; beat = 60 / bpm
rng = np.random.default_rng(39)
def env(on, length, decay):
    e = np.zeros(n); i = int(on * sr); L = int(length * sr)
    if i < n: j = min(n, i + L); e[i:j] = np.exp(-np.arange(j - i) / (decay * sr))
    return e
drums = np.zeros(n); k = 0
while k * beat < secs:
    on = k * beat
    if k % 2 == 0:
        dt_ = np.maximum(t - on, 0.0)
        drums += env(on, 0.25, 0.08) * np.sin(2 * np.pi * (60 + 80 * np.exp(-dt_ * 30)) * dt_) * 0.9
    else: drums += env(on, 0.2, 0.05) * rng.standard_normal(n) * 0.5
    drums += env(on + beat / 2, 0.05, 0.015) * rng.standard_normal(n) * 0.2
    drums += env(on, 0.05, 0.015) * rng.standard_normal(n) * 0.15
    k += 1
roots = [45, 41, 43, 48]
bass = np.zeros(n); other = np.zeros(n); bar = 4 * beat; b = 0
while b * bar < secs:
    f = 440 * 2 ** ((roots[b % 4] - 69) / 12)
    seg = (t >= b * bar) & (t < (b + 1) * bar)
    ph = (t * f) % 1.0
    bass += seg * (2 * ph - 1) * 0.5 * np.minimum(1, (t - b * bar) / 0.01) * np.exp(-(t - b * bar) / (bar * 2))
    for iv in (12, 16, 19):
        fc = 440 * 2 ** ((roots[b % 4] + iv - 69) / 12)
        other += seg * sum(np.sin(2 * np.pi * fc * h * t) / h ** 2 for h in (1, 3, 5)) * 0.12
    b += 1
mel = [64, 67, 69, 67, 64, 62, 60, 62]
vocals = np.zeros(n); i = 0
while i * beat * 2 < secs:
    on = i * beat * 2; seg = (t >= on) & (t < on + beat * 1.8)
    f0 = 440 * 2 ** ((mel[i % 8] - 69) / 12) * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * t))
    phase = 2 * np.pi * np.cumsum(f0) / sr
    tone = sum(np.sin(phase * h) * (1.0 if h in (1, 2, 3) else 0.3) / h for h in range(1, 9))
    vocals += seg * tone * 0.25 * np.minimum(1, (t - on) / 0.05)
    i += 1
def stereo(x, pan):
    x = x / max(1e-9, np.abs(x).max()) * 0.5
    return np.stack([x * (1 - pan), x * pan], axis=1)
S = {"drums": stereo(drums, 0.5), "bass": stereo(bass, 0.5), "vocals": stereo(vocals, 0.5), "other": stereo(other, 0.35)}
mix = sum(S.values()); peak = np.abs(mix).max()
for k in S: S[k] = S[k] / peak * 0.95
mix = mix / peak * 0.95
for k, v in S.items(): sf.write(os.path.join(out, f"{k}.wav"), v, sr, subtype="PCM_16")
sf.write(os.path.join(out, "mix.wav"), mix, sr, subtype="PCM_16")
print(out, secs, "s")
