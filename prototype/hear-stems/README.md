# Prototype: `sf hear stems` — a reference track on mama becomes four stem motifs

Resolves issue #39. Built and measured 2026-10-15, AFK (no ear check; timing and shape are the evidence). Laptop: Intel MacBook Pro. ML box: mama (M2 Pro, 16 GB, Python 3.14, `~/sharpfive-ml-research/.venv-demucs` from #17: demucs 4.1.0, torch 2.14.1). Model: `htdemucs` on MPS through `demucs.api.Separator`. Follows the motif lifecycle (#19, `spec/motif-lifecycle.md`).

## Answer

**Yes. The same ssh + scp shape as `transcribe` fits, and a real 4-minute track round-trips in ~27 s** — 15 s of that is the model, 6 s is bringing four stems home, 1 s is the upload. The reply is the spec's `motifs` list: four audio motifs named `<parent>-drums|bass|vocals|other`, one parent each (the reference track, itself a root motif with a `source: file` sidecar), each with its own `.motif.json`. The map fog "Remote ML job shape" is settled for stems as it was for transcription: **ssh + scp, no service** — and the one thing specific to stems is that **the trip home dominates unless the stems cross the link as FLAC**, which libsndfile writes on mama in 0.3 s per stem with no ffmpeg, and `afconvert` (ships with macOS) turns back into WAV on the laptop.

**Confidence cannot honestly be measured for a separation.** Demucs emits no score, and every cheap proxy I measured (residual, energy share, silence, inter-stem correlation) can tell you a stem is *empty* or the split is *incoherent* — never that it sounds *clean*. The number in the reply is therefore a **prior**: the model's published per-source SDR on MUSDB HQ mapped to a 0–1 "fraction of the stem that is signal rather than error". The measured proxies ride along in an `evidence` block so the agent can say "this track has no vocals" rather than quoting 0.89. Details in [Confidence](#confidence-what-it-can-honestly-mean) below.

## What's here

| File | Role |
|---|---|
| `hear-stems.sh` | laptop `hear stems`: sidecar-if-missing for the reference track (root motif, `source: file`), scp the track + script to `mama:~/sharpfive-hear/`, run, bring the stems back (FLAC by default, `--wire wav` to compare), decode with `afconvert`, print the reply with local paths and a `round_trip_s` breakdown. `--model htdemucs_ft`, `--shifts N`, `--transfer scp|tar`. |
| `stems_mama.py` | the mama side: `Separator.separate_audio_file` → four stems (16-bit WAV or FLAC at the source rate) + one `.wav.motif.json` each (parents = the reference track) + the evidence block + one JSON reply. `--truth DIR` computes SDR against known stems (measurement only). |
| `make_truth.py` | a crude 60 s four-source synth with known stems, for the SDR check. |
| `replies/` | the replies and sidecars from the runs below (`<scratch>` = the session scratch dir). The stems (44 MB each) are not tracked. |

Run: `./hear-stems.sh ~/Downloads/track.mp3` (any format `sphn` decodes — mp3, wav, aiff, flac; no ffmpeg on either machine) → `out/<name>/<name>-{drums,bass,vocals,other}.wav` + sidecars, one JSON line on stdout.

## Reply shape (spec §3 hear + motif lifecycle)

```json
{"status": "done",
 "motifs": [
  {"id": "01M51B6J…", "name": "aint-no-sunshine-drums", "path": ".../aint-no-sunshine-drums.wav", "kind": "audio",
   "parents": ["01M51AW7VXAHY6414ZHBHCKTWB"],
   "provenance": {"source": ".../aint-no-sunshine.mp3", "model": "demucs-htdemucs 4.1.0 / torch 2.14.1 / mps on mama",
                  "at": "2026-10-15T20:13:28-07:00"},
   "confidence": 0.91},
  {"name": "aint-no-sunshine-bass", "confidence": 0.905, "...": "..."},
  {"name": "aint-no-sunshine-vocals", "confidence": 0.887, "...": "..."},
  {"name": "aint-no-sunshine-other", "confidence": 0.814, "...": "..."}],
 "sidecars": {"drums": ".../aint-no-sunshine-drums.wav.motif.json", "...": "..."},
 "audio": {"seconds": 251.69, "sr": 44100, "channels": 2, "stem_bytes_each": 18481049, "wire": "flac"},
 "evidence": {"residual_db": -29.85,
              "rms_share": {"drums": 0.168, "bass": 0.298, "vocals": 0.258, "other": 0.156},
              "silence_frac": {"drums": 0.015, "bass": 0.043, "vocals": 0.032, "other": 0.008},
              "bleed_corr": {"vocals": {"drums": 0.025, "bass": 0.001, "other": 0.113}, "...": "..."},
              "published_sdr_db": {"drums": 10.05, "bass": 9.78, "other": 6.42, "vocals": 8.93},
              "truth_sdr_db": null},
 "timing_s": {"model_load": 1.16, "separate": 14.64, "write": 1.38, "evidence": 0.15, "total": 17.33},
 "round_trip_s": {"upload": 1.05, "mama": 17.76, "download": 5.95, "decode": 1.8, "total": 26.56, "transfer": "scp", "wire": "flac"}}
```

Each stem's sidecar is the §3 sidecar: ULID id, `name`, `kind: audio`, `source: {by: hear, model: demucs-htdemucs, version: 4.1.0, device, host, stem}`, `parents: [<track id>]`, `at`, `tempo/key/bars: null`, `confidence`, empty `text`, empty `placed`. The reference track's sidecar (`<file>.motif.json`, `source: {by: file, path}`) is written by the driver if nothing wrote one before — a FETCHed track would already have one with `source: fetch`.

Two things the ticket text (written before #44) got wrong and the prototype follows the spec on: the reply key is `motifs` (a list of four), not `motif`; and the kind is `audio`, not `stems`. No spec change was needed; `spec/skill/references/hear.md` gained a stems example and a note on what confidence means per verb.

## Measurements

### Wall time, `htdemucs`, MPS (mama)

| Track | Separate | mama total | Upload | Download | Decode | **Round trip** |
|---|---|---|---|---|---|---|
| "Ain't No Sunshine" (mp3, 4:12, 4 MB) — WAV on the wire | 14.8 s | 16.9 s | 1.0 s | 14.2 s (4 × 44 MB) | — | **32.1 s** |
| same — **FLAC on the wire** (default) | 14.6 s | 17.8 s (+1.1 s FLAC encode) | 1.0 s | **6.0 s** (4 × 18 MB) | 1.8 s | **26.6 s** |
| `test240.wav` (synthetic, 4:00, 42 MB) — WAV wire | 14.6 s | 17.1 s | 2.4 s | 13.8 s | — | 33.4 s |
| truth60 (synthetic, 1:00) | 4.1 s | 5.3 s | | | | |

- Model time scales with length: ~3.7 s per audio minute (`htdemucs`, MPS). `htdemucs_ft` (a bag of four fine-tuned models) is **4×**: 57.5 s separate / 60 s total on the real track.
- Model load is 1.0–2.3 s and does *not* need the network: `HF_HUB_OFFLINE=1` loads from the hub cache in 0.7 s (the "unauthenticated requests to the HF Hub" warning on stderr is a version check, harmless).
- **The link is the bottleneck for stems, ~12 MB/s** (laptop ↔ mama over Wi‑Fi/LAN as it stands). Transfer method made no difference: scp 14.3 s, tar-over-ssh 13.9 s, tar + zstd‑1 12.9 s, tar + zstd‑3 12.3 s (zstd only takes 16-bit PCM from 172 MB to 133 MB). **FLAC takes it to 70 MB**: 0.32 s per stem to encode with `soundfile` on mama, 2.1 s to scp one stem, 1.8 s for `afconvert` to decode all four on the laptop. Net: 32 → 27 s. Demucs's own `--flac` flag wants ffmpeg; libsndfile doesn't.
- Upload is cheap when the source is compressed (1.0 s for the 4 MB mp3 vs 2.4 s for the 42 MB WAV). A track that was FETCHed could be fetched *on mama* and skip the upload, but 1–2 s isn't worth a second code path.
- Memory: no swap pressure seen at 16 GB for a 4-minute track; Demucs splits into 7.8 s segments with 25 % overlap, so length isn't a memory problem.

### Ground truth: what the stems actually are

`make_truth.py` renders a 60 s four-source synth (kick/snare/hats from noise bursts and a pitched sine drop; saw bass; triangle-ish chord pad; a vibrato harmonic tone as the "vocal"), so SDR per stem can be computed against the true parts:

| | drums | bass | vocals | other | mix vs Σstems |
|---|---|---|---|---|---|
| `htdemucs` | 8.8 dB | 5.5 dB | **0.0 dB** | **−2.2 dB** | 32.4 dB |
| `htdemucs_ft` | 10.6 dB | 6.3 dB | 0.0 dB | −2.2 dB | 26.2 dB |

The synthetic "vocal" went **entirely into `other`** (vocals SDR 0 = the stem is empty; `other` SDR negative = it carries the vocal on top of the pad). That is not a failure of the split — Demucs's `vocals` means a human voice, and a vibrato sine with harmonics is a synth to it. Drums and bass separate well. The lesson for the honesty question: **on real material the stem labels are the uncertainty**, not the arithmetic — a synth lead, a vocoder, a sampled vocal chop or a distorted bass will land where the model's training set says, and no proxy on the output can tell you which stem a sound *should* have been in.

On the real track, by the same proxies: energy share drums 17 % / bass 30 % / vocals 26 % / other 16 %, under 5 % of 100 ms frames silent in any stem, highest inter-stem correlation 0.11 (vocals↔other). I.e. four live stems and a coherent split — consistent with a full-band recording with a lead vocal, which is what it is. That is as far as the numbers go.

## Confidence: what it can honestly mean

Demucs has no per-stem score. Candidates measured, and what each turned out to mean:

| Proxy | Measured | What it tells you | What it doesn't |
|---|---|---|---|
| **Residual** `mix − Σstems` | −30 dB (real), −21 dB (test240), −32 dB (truth60); `htdemucs_ft` is *worse* (−21 / −26 dB) | Whether the model's four outputs account for the input. htdemucs is a hybrid waveform + spectrogram model with **no sum-to-mix constraint**, so the residual is not zero — the handoff's guess was wrong, and `htdemucs_ft` (four separately fine-tuned models) sums less consistently than the single model while scoring higher per stem | Quality. A model can be perfectly additive and wrong about which stem a sound belongs to |
| **Energy share** per stem | balanced on the real track; vocals 0.01 % on truth60 and 0.3 % on test240 | **An empty stem.** The useful one: "this track has no vocals / no drums" is a sentence the agent should say instead of a number | Whether a non-empty stem is clean |
| **Silence fraction** (100 ms frames < −60 dBFS) | < 5 % real; 19 % on the vocals stem of truth60 with `_ft` | The same thing as energy share, by time rather than energy; catches a stem that exists in the chorus only | Same limit |
| **Bleed** (zero-lag correlation between stems) | all < 0.12 | Gross incoherence (two stems carrying the same material would correlate strongly) | Real bleed is spectrally shaped and partly out of phase; correlation of 0.1 vs 0.03 is noise. On truth60 the vocal sits wholly in `other` and the vocals↔other correlation is 0.05 — the proxy misses exactly the failure that matters |
| **SDR vs ground truth** | only with a truth set | The real measure | Not available for the musician's track, by definition |

So: `confidence` in the reply = `1 / (1 + 10^(−SDR/10))` of the published MUSDB-HQ SDR for that stem and model (Rouard et al. 2023, Table 1: `htdemucs` drums 10.05 / bass 9.78 / other 6.42 / vocals 8.93 dB → 0.91 / 0.905 / 0.887 / 0.814; `htdemucs_ft` 10.08 / 10.39 / 6.32 / 9.20). That is "the fraction of the stem's energy that is signal rather than error, on music like the benchmark's" — a prior, stated as one, and the reason `other` is always the lowest. The `evidence` block carries the measured proxies, and the skill note says what to do with them: an energy share below ~2 % means *the track has no such part*, say that; nothing in the block means *the stem sounds clean*, so never claim it. The threshold of 0.5 in `hear.md` ("show the musician before you build on it") is never crossed by a prior; for stems the rule should be about the evidence instead, which is the one spec question this leaves open (below).

## Known limits (the honest list)

- **No ear check.** AFK ticket; nobody listened to the stems. The numbers say the pipeline is coherent; whether Demucs's vocal on this track is usable as a motif is a listening question, and `other` (6.4 dB published) is the weak stem on every benchmark.
- **The stem labels are the model's taxonomy, not the musician's.** Synth leads go to `other`; a sampled vocal chop may go to `vocals`; anything the training set calls "other" is a grab bag of guitars, keys, pads and effects. Six-stem `htdemucs_6s` (+guitar, piano) exists, 22 s per 4 min in #17, piano "not working great" per upstream — a spec question, not a prototype one.
- **Confidence is a prior.** Two different tracks get identical numbers from the same model. If the musician asks "how good is this split", the honest answer is the published benchmark plus the evidence block, not the number.
- **The link is 12 MB/s and the stems are 4× the input.** FLAC halves it; a 10-minute track still costs ~15 s coming home. If mama ever moves off the LAN, stems should stay on mama until a motif is placed — a stage-4 question.
- **Not deterministic on MPS** (as with #38); re-runs differ at the LSB. Sidecar ids and `at` are new on every run; a re-run of the same track is a new set of four motifs, and nothing dedupes them. The driver wipes `out/<name>` on mama before each run; locally it overwrites.
- **mp3 parents put the stems 25 ms late.** Found on the ear check (2026-10-16, summing the stems against the original): mama's decoder (`sphn`, used by Demucs 4.1.0) keeps the mp3 encoder/decoder delay, macOS `afconvert` (and so Logic) trims it, so the stems sit **1105 samples** after the original as the laptop decodes it (stems 11 099 520 frames, afconvert 11 098 944; residual drops from +3 dB to −30 dB once shifted). A WAV/AIFF parent has no offset. Fix for the real verb: when the input is mp3 (or any lossy format with a delay header), drop the first 1105 samples of each stem before writing, or decode the parent on the laptop and ship the WAV. Until then, stems from an mp3 parent are not sample-aligned to it in Logic.
- **Clipping:** Demucs rescales a stem whose peak exceeds 0.99 (`clip: rescale`); the FLAC path copies that rule. A stem can therefore be quieter than it was in the mix, by at most a fraction of a dB on the tracks tried.
- **One real track, two synthetic ones.** Enough for timing and shape; nothing here is a quality claim.

## Open for the spec

- `hear.md`'s "confidence below 0.5: show the musician" rule is meaningless for stems. Suggested: for stems, the gate is the evidence — energy share < 2 % → say the part is absent; otherwise state the model's published quality once per session and move on.
- Whether `hear stems` should offer `--two-stems vocals` (vocal / instrumental, Demucs supports it in one pass at the same cost) and `htdemucs_6s`. Both are flags on the same pipeline; the question is what the motif list looks like (two motifs? six?) and whether `<parent>-no_vocals` is a motif name a musician would want.
- Where fetched reference tracks live when mama fetched them; today the laptop always holds the parent.
