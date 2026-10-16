#!/usr/bin/env python3
"""sf hear stems — the mama side.

A reference track in, four audio motifs out (spec/motif-lifecycle.md §4: drums, bass, vocals, other,
named <parent>-drums etc., one parent each = the reference track). Demucs 4.1.0 `htdemucs` on MPS via
demucs.api.Separator; stems written as 16-bit WAV at the source rate.

Reply (stdout, one JSON object) follows spec/tool-schemas.md §3:
  {status: done|failed, motifs: [{id, name, path, kind: audio, parents, provenance: {source, model, at}, confidence}, ...], ...}
plus one <file>.wav.motif.json sidecar beside each stem.

Confidence: Demucs gives no per-stem score. The number here is a prior from the model's published
MUSDB-HQ SDR for that stem, mapped to the fraction of stem energy that is signal rather than error
(1 / (1 + 10^(-SDR/10))). The measured proxies (residual, RMS share, silence, bleed) are reported as
`evidence` and are *not* folded in — see README for why.

Run inside ~/sharpfive-ml-research/.venv-demucs on mama (torch 2.14, demucs 4.1.0).
"""
import argparse, json, os, sys, time, datetime, platform, secrets
import numpy as np

STEMS = ["drums", "bass", "vocals", "other"]
# Rouard, Massa, Défossez, "Hybrid Transformers for Music Source Separation" (ICASSP 2023, arXiv:2211.08553),
# Table 1, MUSDB HQ test set, SDR per source (dB). The released `htdemucs` is the row trained with 800 extra
# songs (All 8.80); `htdemucs_ft` is the per-source fine-tuned row (All 9.00). No figure is published for the
# 6-source model; it reuses the htdemucs row.
PUBLISHED_SDR = {
    "htdemucs":    {"drums": 10.05, "bass": 9.78, "other": 6.42, "vocals": 8.93},
    "htdemucs_ft": {"drums": 10.08, "bass": 10.39, "other": 6.32, "vocals": 9.20},
    "htdemucs_6s": {"drums": 10.05, "bass": 9.78, "other": 6.42, "vocals": 8.93},
}

def ulid():
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    v = (int(time.time() * 1000) << 80) | secrets.randbits(80)
    return "".join(alphabet[(v >> (5 * i)) & 31] for i in range(25, -1, -1))

def log(*a):
    print(*a, file=sys.stderr, flush=True)

def db(x):
    return float(10 * np.log10(max(x, 1e-20)))

def sdr(ref, est):
    ref = ref.astype(np.float64); est = est.astype(np.float64)
    return db((ref ** 2).sum() / max(((ref - est) ** 2).sum(), 1e-20))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default="htdemucs")
    ap.add_argument("--device", default="mps")
    ap.add_argument("--shifts", type=int, default=0, help="test-time augmentation; each shift is another full pass")
    ap.add_argument("--bits", type=int, default=16, choices=[16, 24])
    ap.add_argument("--parent", default=None, help="the reference track's motif id (ULID)")
    ap.add_argument("--name", default=None, help="parent motif name; stems are <name>-drums etc.")
    ap.add_argument("--truth", default=None, help="dir with drums.wav bass.wav vocals.wav other.wav ground truth → SDR per stem")
    ap.add_argument("--wire", default="wav", choices=["wav", "flac"],
                    help="flac: write FLAC (libsndfile, no ffmpeg) for the trip home; the laptop decodes to WAV. Sidecar and reply name the final .wav")
    a = ap.parse_args()

    t0 = time.time()
    os.makedirs(a.out, exist_ok=True)
    base = a.name or os.path.splitext(os.path.basename(a.audio))[0]
    try:
        import torch, demucs
        from demucs.api import Separator, save_audio
    except Exception as e:
        print(json.dumps({"status": "failed", "reason": "deps-missing", "hint": str(e)})); return 1
    device = a.device
    if device == "mps" and not torch.backends.mps.is_available():
        device = "cpu"
    sep = Separator(model=a.model, device=device, shifts=a.shifts, progress=False)
    t_model = time.time() - t0

    t1 = time.time()
    origin, separated = sep.separate_audio_file(a.audio)     # origin: (ch, n) at sep.samplerate
    if device == "mps":
        torch.mps.synchronize()
    t_sep = time.time() - t1
    sr = sep.samplerate

    # write stems
    t2 = time.time()
    paths, wire_paths = {}, {}
    for s in STEMS:
        p = os.path.join(a.out, f"{base}-{s}.wav")
        if a.wire == "flac":
            import soundfile as sf
            w = separated[s]
            peak = float(w.abs().max())
            if peak > 0.99:                       # same rescale rule as demucs.api.save_audio
                w = w / peak * 0.99
            wp = os.path.join(a.out, f"{base}-{s}.flac")
            sf.write(wp, w.cpu().numpy().T, sr, format="FLAC", subtype="PCM_16" if a.bits == 16 else "PCM_24")
            wire_paths[s] = wp
        else:
            save_audio(separated[s], p, samplerate=sr, bits_per_sample=a.bits, clip="rescale")
            wire_paths[s] = p
        paths[s] = p
    t_write = time.time() - t2

    # evidence
    t3 = time.time()
    mix = origin.cpu().numpy()
    est = {s: separated[s].cpu().numpy() for s in STEMS}
    n = mix.shape[1]
    e_mix = float((mix ** 2).sum())
    summed = sum(est.values())
    resid = mix - summed
    e_resid = float((resid ** 2).sum())
    shares = {s: float((est[s] ** 2).sum()) / max(e_mix, 1e-20) for s in STEMS}
    frame = int(sr * 0.1)
    def silence_frac(x, floor_db=-60.0):
        nf = n // frame
        peaks = np.abs(x[:, :nf * frame]).reshape(x.shape[0], nf, frame).max(axis=(0, 2))
        return float((20 * np.log10(peaks + 1e-9) < floor_db).mean())
    sil = {s: silence_frac(est[s]) for s in STEMS}
    # bleed: normalised zero-lag correlation between stems (mono-summed). Stems of one mix are time-aligned.
    mono = {s: est[s].mean(axis=0) for s in STEMS}
    norms = {s: float(np.sqrt((mono[s] ** 2).sum()) + 1e-12) for s in STEMS}
    corr = {s: {t: round(float(np.dot(mono[s], mono[t]) / (norms[s] * norms[t])), 4) for t in STEMS if t != s} for s in STEMS}
    truth_sdr = None
    if a.truth:
        import soundfile as sf
        truth_sdr = {}
        for s in STEMS:
            ref, tsr = sf.read(os.path.join(a.truth, f"{s}.wav"), dtype="float32", always_2d=True)
            ref = ref.T
            m = min(ref.shape[1], n)
            truth_sdr[s] = round(sdr(ref[:, :m], est[s][:, :m]), 2)
        truth_sdr["mix_vs_sum"] = round(sdr(mix, summed), 2)
    t_evidence = time.time() - t3

    prior = PUBLISHED_SDR.get(a.model, PUBLISHED_SDR["htdemucs"])
    conf = {s: round(1.0 / (1.0 + 10 ** (-prior[s] / 10.0)), 3) for s in STEMS}

    ver = getattr(demucs, "__version__", "4.1.0")
    model_str = f"demucs-{a.model} {ver} / torch {torch.__version__} / {device} on {platform.node()}"
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    motifs, sidecars = [], {}
    for s in STEMS:
        sc = {"id": ulid(), "name": f"{base}-{s}", "kind": "audio",
              "source": {"by": "hear", "model": f"demucs-{a.model}", "version": ver, "device": device, "host": platform.node(), "stem": s},
              "parents": [a.parent] if a.parent else [],
              "at": now, "tempo": None, "key": None, "bars": None,
              "confidence": conf[s], "text": "", "placed": []}
        scp = paths[s] + ".motif.json"
        with open(scp, "w") as fh:
            json.dump(sc, fh, indent=1)
        sidecars[s] = scp
        motifs.append({"id": sc["id"], "name": sc["name"], "path": paths[s], "kind": "audio", "parents": sc["parents"],
                       "provenance": {"source": os.path.abspath(a.audio), "model": model_str, "at": now},
                       "confidence": conf[s]})
    reply = {
        "status": "done",
        "motifs": motifs,
        "sidecars": sidecars,
        "audio": {"seconds": round(n / sr, 3), "sr": sr, "channels": int(mix.shape[0]),
                  "stem_bytes_each": os.path.getsize(wire_paths["drums"]), "wire": a.wire},
        "evidence": {
            "residual_db": round(db(e_resid / max(e_mix, 1e-20)), 2),
            "rms_share": {s: round(shares[s], 4) for s in STEMS},
            "silence_frac": {s: round(sil[s], 3) for s in STEMS},
            "bleed_corr": corr,
            "published_sdr_db": prior,
            "truth_sdr_db": truth_sdr,
        },
        "timing_s": {"model_load": round(t_model, 3), "separate": round(t_sep, 3), "write": round(t_write, 3),
                     "evidence": round(t_evidence, 3), "total": round(time.time() - t0, 3)},
    }
    print(json.dumps(reply))
    return 0

if __name__ == "__main__":
    sys.exit(main())
