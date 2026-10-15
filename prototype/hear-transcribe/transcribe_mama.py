#!/usr/bin/env python3
"""sf hear transcribe — the mama side.

A hummed take (WAV) in, a MIDI motif out (spec/motif-lifecycle.md: the take is the parent). torchcrepe `full` at a 5 ms hop,
periodicity-thresholded, median-filtered, segmented into notes. Note starts and
lengths are kept exactly where they were sung (no quantise); the grid is only
used to express the feel as an offset from the nearest 16th.

Reply (stdout, one JSON object) follows spec/tool-schemas.md §3:
  {status: done|failed, motif: {id, name, path, kind: midi, parents, provenance: {source, model, at}, confidence}, ...}
plus the sidecar <file>.motif.json beside the MIDI.

Run inside ~/sharpfive-ml-research/.venv-mir on mama (torch 2.14, torchcrepe 0.0.24, pretty_midi).
"""
import argparse, json, math, sys, time, datetime, os, platform, secrets
import numpy as np

def ulid():
    """26-char Crockford base32: 48-bit ms timestamp + 80 random bits."""
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    v = (int(time.time() * 1000) << 80) | secrets.randbits(80)
    return "".join(alphabet[(v >> (5 * i)) & 31] for i in range(25, -1, -1))

def log(*a):
    print(*a, file=sys.stderr, flush=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("--out", required=True, help="output directory")
    ap.add_argument("--bpm", type=float, default=None, help="click tempo of the take; MIDI tempo + feel grid")
    ap.add_argument("--grid-start", type=float, default=0.0, help="seconds into the file where bar 1 beat 1 falls (after the count-in)")
    ap.add_argument("--model", default="full", choices=["tiny", "full"])
    ap.add_argument("--device", default="mps")
    ap.add_argument("--hop-ms", type=float, default=10.0, help="CREPE native step; 5 ms doubles the cost for no gain on hums")
    ap.add_argument("--fmin", type=float, default=50.0)
    ap.add_argument("--fmax", type=float, default=1000.0)
    ap.add_argument("--periodicity", type=float, default=0.21, help="voicing threshold (torchcrepe default .21)")
    ap.add_argument("--silence-db", type=float, default=-80.0, help="torchcrepe default -60 zeroed most of a quiet laptop-mic hum")
    ap.add_argument("--min-note-ms", type=float, default=60.0)
    ap.add_argument("--split-semitones", type=float, default=0.8, help="pitch move that starts a new note")
    ap.add_argument("--hold-ms", type=float, default=100.0, help="the move must hold this long")
    ap.add_argument("--merge-gap-ms", type=float, default=50.0)
    ap.add_argument("--pitch-window", type=float, nargs=2, default=(0.4, 0.9), help="fraction of the note the pitch is read from; late, because scoops come in from below")
    ap.add_argument("--tuning-centre", dest="tuning_centre", action="store_true", help="shift by the take's mean cents offset before rounding; off by default (fixed one peak, broke one passing note on take 2)")
    ap.add_argument("--rearticulate-db", type=float, default=3.0, help="energy dip-and-rise inside a note that counts as a new note")
    ap.add_argument("--stub-ms", type=float, default=130.0, help="shorter and unsure = stutter, absorbed by a neighbour")
    ap.add_argument("--stub-confidence", type=float, default=0.25)
    ap.add_argument("--glide-ms", type=float, default=150.0, help="a shorter note leading into a longer semitone neighbour is a scoop")
    ap.add_argument("--parent", default=None, help="the take motif's id (ULID)")
    ap.add_argument("--name", default=None, help="motif name; default = the take's base name")
    ap.add_argument("--render", action="store_true", help="also write a sine rendering of the MIDI for an ear check")
    a = ap.parse_args()

    t0 = time.time()
    os.makedirs(a.out, exist_ok=True)
    stem = os.path.splitext(os.path.basename(a.wav))[0]
    try:
        import soundfile as sf, torch, torchcrepe, pretty_midi
    except Exception as e:
        print(json.dumps({"status": "failed", "reason": "deps-missing", "hint": str(e)})); return 1

    audio, sr = sf.read(a.wav, dtype="float32", always_2d=True)
    audio = audio.mean(axis=1)
    dur = len(audio) / sr
    t_load = time.time() - t0

    device = a.device
    if device == "mps" and not torch.backends.mps.is_available():
        device = "cpu"
    hop = int(round(sr * a.hop_ms / 1000.0))
    x = torch.tensor(audio)[None]
    t1 = time.time()
    try:
        f0, per = torchcrepe.predict(x, sr, hop_length=hop, fmin=a.fmin, fmax=a.fmax, model=a.model,
                                     device=device, batch_size=512, return_periodicity=True)
    except Exception as e:
        if device != "cpu":
            log("mps failed, falling back to cpu:", e)
            device = "cpu"
            f0, per = torchcrepe.predict(x, sr, hop_length=hop, fmin=a.fmin, fmax=a.fmax, model=a.model,
                                         device=device, batch_size=512, return_periodicity=True)
        else:
            raise
    t_infer = time.time() - t1

    # clean: silence → unvoiced, median filter periodicity + f0, threshold
    win = 3
    per = torchcrepe.filter.median(per, win)
    per = torchcrepe.threshold.Silence(a.silence_db)(per, x, sr, hop)
    f0c = torchcrepe.threshold.At(a.periodicity)(f0, per)
    f0c = torchcrepe.filter.mean(f0c, win)
    f0n = f0c[0].cpu().numpy(); pern = per[0].cpu().numpy(); f0raw = f0[0].cpu().numpy()
    n = len(f0n); dt = hop / sr
    times = np.arange(n) * dt
    midi = np.full(n, np.nan)
    v = ~np.isnan(f0n) & (f0n > 0)
    midi[v] = 69 + 12 * np.log2(f0n[v] / 440.0)

    # segment: runs of voiced frames; inside a run, a new note starts only when the smoothed pitch
    # leaves the current note's running median by > split_semitones AND stays away for hold_ms.
    # Vibrato straddling a semitone boundary therefore stays one note.
    min_frames = max(1, int(round(a.min_note_ms / 1000.0 / dt)))
    hold = max(1, int(round(a.hold_ms / 1000.0 / dt)))
    sm_win = max(1, int(round(0.08 / dt)) | 1)           # ~80 ms median smoothing for the decision only
    midi_s = midi.copy()
    for k in range(n):
        if v[k]:
            lo = max(0, k - sm_win // 2); hi = min(n, k + sm_win // 2 + 1)
            midi_s[k] = np.nanmedian(midi[lo:hi])
    notes = []
    i = 0
    while i < n:
        if not v[i]:
            i += 1; continue
        j = i
        while j < n and v[j]:
            j += 1
        start = i
        k = i + 1
        while k < j:
            ref = np.nanmedian(midi_s[start:k])
            if abs(midi_s[k] - ref) > a.split_semitones:
                end = min(k + hold, j)
                if end - k >= hold and np.all(np.abs(midi_s[k:end] - ref) > a.split_semitones):
                    notes.append((start, k)); start = k
                    k = end
                    continue
            k += 1
        notes.append((start, j))
        i = j
    # merge same-pitch neighbours separated by a tiny gap (breath flicker)
    merged = []
    for (s_, e_) in notes:
        if merged:
            ps, pe = merged[-1]
            gap = s_ - pe
            if gap * dt <= a.merge_gap_ms / 1000.0 and round(float(np.nanmedian(midi[ps:pe]))) == round(float(np.nanmedian(midi[s_:e_]))):
                merged[-1] = (ps, e_); continue
        merged.append((s_, e_))
    notes = merged
    # fold scoops: a short note (< glide_ms) that runs straight into a longer neighbour one
    # semitone away is the onset glide of that neighbour, not a note of its own
    glide = max(1, int(round(a.glide_ms / 1000.0 / dt)))
    folded = []
    k = 0
    while k < len(notes):
        s_, e_ = notes[k]
        if e_ - s_ < glide and k + 1 < len(notes):
            ns, ne = notes[k + 1]
            if ns - e_ <= 2 and (ne - ns) >= (e_ - s_) and 0 < abs(round(float(np.nanmedian(midi[s_:e_]))) - round(float(np.nanmedian(midi[ns:ne])))) <= 1:
                notes[k + 1] = (s_, ne)   # neighbour inherits the glide's start; its pitch comes from its stable middle
                k += 1; continue
        folded.append((s_, e_)); k += 1
    notes = folded
    # re-articulations: repeated notes on one pitch show as energy onsets inside a run, not pitch changes
    try:
        import librosa
        oenv = librosa.onset.onset_strength(y=audio, sr=sr, hop_length=hop)
        oframes = librosa.onset.onset_detect(onset_envelope=oenv, sr=sr, hop_length=hop, units="frames", backtrack=True)
        oset = set(int(o) for o in oframes)
    except Exception as e:
        log("onset detection unavailable:", e); oset = set()
    # softer re-articulations (legato "da-da"): an energy dip then a rise of >= rearticulate_db inside a note
    try:
        import librosa as _l
        rms_db = 20 * np.log10(_l.feature.rms(y=audio, frame_length=2048, hop_length=hop)[0] + 1e-9)
        rms_db = rms_db[:n] if len(rms_db) >= n else np.pad(rms_db, (0, n - len(rms_db)), constant_values=-90)
        look = max(1, int(round(0.15 / dt)))
        for k in range(look, n - look):
            dip = rms_db[k]; before = rms_db[k - look:k].max(); after = rms_db[k + 1:k + look + 1].max()
            if before - dip >= a.rearticulate_db and after - dip >= a.rearticulate_db:
                oset.add(k)
    except Exception as e:
        log("rms re-articulation unavailable:", e)
    split = []
    guard = max(1, int(round(0.08 / dt)))         # an onset within 80 ms of a note edge is that edge
    for (s_, e_) in notes:
        stub_fr = max(min_frames, int(round(a.stub_ms / 1000.0 / dt)))
        cuts = sorted(o for o in oset if s_ + guard <= o <= e_ - guard)
        last = s_
        for c in cuts:
            if c - last >= stub_fr and e_ - c >= stub_fr:
                split.append((last, c)); last = c
        split.append((last, e_))
    notes = split

    # tuning centre of the take: singers sit a little flat or sharp of A440 as a whole; measure it on the
    # late window of every note and remove it before rounding, so boundary cases round the way the singer meant
    centre = 0.0
    if a.tuning_centre:
        angs, ws = [], []
        for (s, e) in notes:
            if e - s < min_frames: continue
            lo = s + int((e - s) * a.pitch_window[0]); hi = max(lo + 1, s + int((e - s) * a.pitch_window[1]))
            pf = float(np.nanmedian(midi[lo:hi])); angs.append((pf - round(pf)) * 2 * np.pi); ws.append(e - s)
        if ws:
            ws = np.array(ws); angs = np.array(angs)
            centre = float(np.arctan2((ws * np.sin(angs)).sum(), (ws * np.cos(angs)).sum()) / (2 * np.pi))
    def describe(s, e):
        m = midi[s:e]; p = pern[s:e]
        lo = s + int((e - s) * a.pitch_window[0]); hi = max(lo + 1, s + int((e - s) * a.pitch_window[1]))
        pitch_f = float(np.nanmedian(midi[lo:hi])) - centre
        pitch = int(round(pitch_f))
        stable = float(np.mean(np.abs((m - centre) - pitch) <= 0.5))
        conf = float(np.nanmean(p)) * stable
        t_on = float(times[s]); t_off = float(times[e - 1] + dt)
        rec = {"pitch": pitch, "name": pretty_midi.note_number_to_name(pitch), "cents": round((pitch_f - pitch) * 100),
               "start_s": round(t_on, 4), "end_s": round(t_off, 4), "confidence": round(conf, 3),
               "periodicity": round(float(np.nanmean(p)), 3), "stable": round(stable, 3)}
        if a.bpm:
            beat = 60.0 / a.bpm
            b_on = (t_on - a.grid_start) / beat
            nearest16 = round(b_on * 4) / 4
            rec["beat"] = round(b_on + 1, 3)            # 1-based beats from bar 1 beat 1
            rec["offset_ms"] = round((b_on - nearest16) * beat * 1000)
            rec["length_beats"] = round((t_off - t_on) / beat, 3)
        return rec

    spans = [(s, e) for (s, e) in notes if e - s >= min_frames]
    raw_notes = [describe(s, e) for (s, e) in spans]

    # cleanup: a stub (short and unsure) is a stutter, not a note. It joins the neighbour it touches
    # (the previous span if contiguous, else the next); pitch and confidence are recomputed over the union.
    stub_fr = int(round(a.stub_ms / 1000.0 / dt)); touch = int(round(0.03 / dt))
    changed = True
    while changed and len(spans) > 1:
        changed = False
        for k, (s, e) in enumerate(spans):
            if e - s < stub_fr and describe(s, e)["confidence"] < a.stub_confidence:
                if k > 0 and s - spans[k - 1][1] <= touch:
                    spans[k - 1] = (spans[k - 1][0], e)
                elif k + 1 < len(spans) and spans[k + 1][0] - e <= touch:
                    spans[k + 1] = (s, spans[k + 1][1])
                else:
                    continue
                spans.pop(k); changed = True; break
    out_notes = [describe(s, e) for (s, e) in spans]
    tc_ver = getattr(torchcrepe, '__version__', '0.0.24')

    # overall confidence: duration-weighted note confidence, scaled by how much of the voiced time became notes
    if out_notes:
        w = np.array([r["end_s"] - r["start_s"] for r in out_notes]); c = np.array([r["confidence"] for r in out_notes])
        covered = w.sum() / max(1e-9, v.sum() * dt)
        confidence = float((w * c).sum() / w.sum() * min(1.0, covered))
    else:
        confidence = 0.0

    # MIDI: tempo = click tempo (or 120), times relative to grid start, unquantised
    bpm = a.bpm or 120.0
    pm = pretty_midi.PrettyMIDI(initial_tempo=bpm)
    inst = pretty_midi.Instrument(program=0, name="hum")
    for r in out_notes:
        s = max(0.0, r["start_s"] - a.grid_start); e = max(s + 0.01, r["end_s"] - a.grid_start)
        vel = int(np.clip(40 + 87 * r["confidence"], 40, 127))
        inst.notes.append(pretty_midi.Note(velocity=vel, pitch=r["pitch"], start=s, end=e))
    pm.instruments.append(inst)
    midi_path = os.path.join(a.out, stem + ".mid")
    pm.write(midi_path)

    # raw curve sidecar
    f0_path = os.path.join(a.out, stem + ".f0.csv")
    with open(f0_path, "w") as fh:
        fh.write("t,f0_raw,f0_voiced,periodicity\n")
        for t, fr, fv, p in zip(times, f0raw, f0n, pern):
            fh.write(f"{t:.4f},{fr:.2f},{'' if np.isnan(fv) else f'{fv:.2f}'},{p:.3f}\n")

    render_path = None
    if a.render:
        rs = 44100
        total = (max([r["end_s"] for r in out_notes]) if out_notes else 1.0) + 0.5
        y = np.zeros(int(total * rs), dtype=np.float32)
        for r in out_notes:
            s = int(r["start_s"] * rs); e = int(r["end_s"] * rs)
            tt = np.arange(e - s) / rs
            f = 440.0 * 2 ** ((r["pitch"] - 69) / 12)
            env = np.minimum(1, tt / 0.01) * np.minimum(1, (tt[-1] - tt) / 0.03 + 1e-9) if len(tt) else tt
            y[s:e] += (0.4 * np.sin(2 * np.pi * f * tt) * env).astype(np.float32)
        if a.bpm:  # click on the grid underneath
            beat = 60.0 / a.bpm
            k = 0
            while True:
                tc = a.grid_start + k * beat
                if tc > total: break
                s = int(tc * rs); L = int(0.01 * rs)
                if 0 <= s < len(y) - L:
                    y[s:s + L] += (0.3 if k % 4 == 0 else 0.15) * np.sign(np.sin(2 * np.pi * 2000 * np.arange(L) / rs)).astype(np.float32)
                k += 1
        render_path = os.path.join(a.out, stem + ".render.wav")
        sf.write(render_path, y, rs, subtype="PCM_16")

    model_str = f"torchcrepe-{a.model} {tc_ver} / torch {torch.__version__} / {device} on {platform.node()}"
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    name = a.name or stem
    last_beat = max([r["beat"] + r["length_beats"] for r in out_notes], default=1.0) if a.bpm else None
    bars = int(math.ceil((last_beat - 1) / 4)) if last_beat else None
    sidecar = {
        "id": ulid(), "name": name, "kind": "midi",
        "source": {"by": "hear", "model": f"torchcrepe-{a.model}", "version": tc_ver, "device": device, "host": platform.node()},
        "parents": [a.parent] if a.parent else [],
        "at": now, "tempo": a.bpm, "key": None, "bars": bars,
        "confidence": round(confidence, 3), "text": "", "placed": [],
    }
    sidecar_path = midi_path + ".motif.json"
    with open(sidecar_path, "w") as fh:
        json.dump(sidecar, fh, indent=1)
    reply = {
        "status": "done" if out_notes else "failed",
        "motif": {
            "id": sidecar["id"], "name": name, "path": midi_path, "kind": "midi", "parents": sidecar["parents"],
            "provenance": {"source": os.path.abspath(a.wav), "model": model_str, "at": now},
            "confidence": round(confidence, 3),
        },
        "notes": out_notes,
        "raw_notes": raw_notes,
        "tuning_centre_cents": round(centre * 100),
        "sidecars": {"motif": sidecar_path, "f0": f0_path, "render": render_path},
        "audio": {"seconds": round(dur, 3), "sr": sr, "voiced_seconds": round(float(v.sum() * dt), 3)},
        "timing_s": {"load": round(t_load, 3), "infer": round(t_infer, 3), "total": round(time.time() - t0, 3)},
    }
    if not out_notes:
        reply["reason"] = "no-voiced-notes"; reply["hint"] = "Nothing pitched was found. Hum closer to the mic, or longer."
    print(json.dumps(reply))
    return 0

if __name__ == "__main__":
    sys.exit(main())
