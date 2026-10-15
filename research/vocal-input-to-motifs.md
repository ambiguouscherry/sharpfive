# Research: interpreting non-textual vocal input (hum, sing, beatbox) into Motifs

Resolves issue #22. Researched 2026-10-10 against the model papers, their official repos, library docs, and dataset records. Desk research only — nothing was installed or run on the laptop. Sibling ticket #17 covers general stem separation and transcription of *recorded music*; this note is only about the **musician's own voice** as a motif (CONTEXT.md: *Vocalization* — "singing, humming, beatboxing, mouth-drumming … the agent must interpret (melody, rhythm, feel) rather than transcribe as words").

## TL;DR / Recommendation

**Record-then-process is the v1.** The musician records a short take (count-in to a click, dry room, one phrase at a time) on the laptop; the agent ships the WAV to mama and runs two parallel paths:

1. **Melody path (hum/sing):** monophonic f0 tracking with **CREPE** (via `torchcrepe` or `penn`, since the original `crepe` needs TensorFlow, which has no stable Python 3.14 wheel) → voicing-threshold + median filter → segment into notes → quantise to the click grid → MIDI. `librosa.pyin` is the zero-dependency fallback; **Basic Pitch** is the "give me a MIDI file" shortcut (CoreML/ONNX backends, 16 k parameters, 11 ms hop) but is polyphonic-first and runs on Python ≤ 3.11 as published.
2. **Rhythm path (beatbox/mouth-drum):** `librosa.onset.onset_detect` for hits → per-hit **kick/snare/closed-hat/open-hat** classification by kNN on a few dozen labelled examples *from this musician* (the literature is unanimous that user-specific models beat general ones: ~0.90 vs ~0.73 accuracy) → `librosa.beat.beat_track` (or just the click) for tempo → micro-timing offsets from the grid kept as the *feel*.

Both paths emit a motif: a MIDI region plus provenance (source WAV, model, confidence per note/hit). Expect **near-perfect pitch on clean sustained humming** (CREPE ≥ 0.95 raw pitch accuracy at 25 cents on synthetic stems), **~90% drum-class accuracy** with per-user training, and **weak-but-usable tempo** from an unaccompanied groove (a click fixes it). End-to-end latency for a 4-bar take is seconds, dominated by file transfer, not inference.

**Live turn-taking is a stage-4 concern**, not v1: it needs streaming capture on the laptop (`sounddevice` callback, CoreAudio), a streaming pitch/onset frontend (~64–100 ms inherent algorithmic latency), the ML either on the laptop CPU (CREPE-tiny / pyin are feasible) or over a low-latency link to mama, and a conversational protocol for "I'm done, your turn".

**Also worth knowing:** Logic itself ships a hum-to-MIDI path — Flex Pitch → *Edit > Create MIDI Track from Flex Pitch Data* (monophonic material only) — reachable via the UI-scripting limb with no ML at all. That is a legitimate zero-infrastructure fallback for the melody case.

## 1. Hum / sing → melody

### 1.1 Candidates

| Tool | What it is | Runtime | Resolution | Notes |
|---|---|---|---|---|
| **CREPE** ([Kim, Salamon, Li, Bello, ICASSP 2018](https://arxiv.org/abs/1802.06182); [repo](https://github.com/marl/crepe)) | CNN on raw 16 kHz waveform, 1024-sample (≈64 ms) window, 360 bins × 20 cents, voicing confidence | TensorFlow ≥ 2.0 (original); PyTorch ports below | 10 ms step default | Five capacities `tiny…full`; Viterbi smoothing optional, off by default |
| **torchcrepe** ([repo](https://github.com/maxrmorrison/torchcrepe)) | PyTorch port of CREPE, `tiny` and `full` only | PyTorch | user-set hop (example 5 ms) | Viterbi default; `return_periodicity`, `threshold.At`, `threshold.Silence(-60)`, median/mean filters built in |
| **penn / FCNF0++** ([repo](https://github.com/interactiveaudiolab/penn)) | Newer neural pitch+periodicity estimator, trained on MDB-stem-synth + PTDB | PyTorch, `pip install penn` | 10 ms default, 31–1984 Hz | Per-frame inference, optional Viterbi (`torbi` for speed); voicing threshold `interp_unvoiced_at` default 0.1625 |
| **pYIN** ([Mauch & Dixon 2014](https://ieeexplore.ieee.org/document/6853678); [`librosa.pyin`](https://librosa.org/doc/0.11.0/generated/librosa.pyin.html)) | Probabilistic YIN with HMM voicing | pure Python (librosa/numba) | frame 2048 @ 22.05 kHz (≈93 ms), hop = frame/4 (≈23 ms) by default | Returns `f0`, `voiced_flag`, `voiced_prob`; `fmin`/`fmax` required (doc suggests C2 ≈ 65 Hz as fmin) |
| **SPICE** ([Gfeller et al. 2020](https://arxiv.org/abs/1910.11664)) | Self-supervised CQT-shift model, monophonic, with confidence head | TensorFlow / TF Hub | — | "accuracy comparable to fully supervised models"; no advantage over CREPE for us and shares the TF dependency problem — **not recommended** |
| **Basic Pitch** ([Bittner et al., ICASSP 2022](https://arxiv.org/abs/2203.09893); [repo](https://github.com/spotify/basic-pitch); [PyPI 0.4.0, Aug 2024](https://pypi.org/project/basic-pitch/)) | Lightweight (16,782 params) polyphonic note + multipitch + onset model, outputs MIDI with pitch bends | TF / **CoreML** / TFLite / ONNX; classifiers Python 3.8–3.11, "Apple M1: only 3.10" | CQT hop ≈ 11 ms | Trained on GuitarSet, MAESTRO, Slakh, **iKala, MedleyDB** (so vocals are in the training set); README: "works best on one instrument at a time"; vocal test set is Molina, where the vocal-specialist Vocano beats it on note F-measure |

### 1.2 Accuracy expectations

CREPE paper, Table 2, raw pitch accuracy (fraction of voiced frames within threshold), mean ± std:

| Dataset | Threshold | CREPE | pYIN | SWIPE |
|---|---|---|---|---|
| RWC-synth | 50 ¢ | 0.999 | 0.990 | 0.963 |
| RWC-synth | 25 ¢ | 0.999 | 0.972 | 0.949 |
| RWC-synth | 10 ¢ | 0.995 | 0.908 | 0.833 |
| MDB-stem-synth | 50 ¢ | 0.967 ± 0.091 | 0.919 ± 0.129 | 0.925 ± 0.116 |
| MDB-stem-synth | 25 ¢ | 0.953 ± 0.103 | 0.890 ± 0.134 | 0.897 ± 0.127 |
| MDB-stem-synth | 10 ¢ | 0.909 ± 0.126 | 0.826 ± 0.150 | 0.816 ± 0.165 |

Source: [arXiv 1802.06182 HTML](https://arxiv.org/html/1802.06182v1). These are frame-level numbers on resynthesised stems, i.e. a ceiling. For a hummed phrase through a laptop mic, the practical errors are **not** pitch errors; they are:

- **Octave/voicing flicker at note boundaries and on breathy or glottal onsets** — handled by the confidence/periodicity threshold (torchcrepe's `threshold.At(.21)`, penn's 0.1625 default) plus a median filter, then Viterbi if still noisy.
- **Note segmentation** — f0 trackers give a curve, not notes. Humming legato means pitch glides, so segmentation is "new note when the median-filtered pitch moves > ~50 cents and stays there for > N frames". Basic Pitch does this internally (frame + onset heads) and is the better choice when the musician articulates ("da-da-da") rather than hums smoothly; a glide-heavy hum can confuse its onset head.
- **Vibrato and scooping** — quantise to the nearest semitone over the note's *stable* portion, not its onset; keep the raw f0 curve in the motif so pitch-bend can be reconstructed later if wanted.
- **Key/octave** — a hum is often an octave below the intended instrument. Report the MIDI as sung; let the WRITE verb transpose.

### 1.3 What runs on mama (Python 3.14, M2 Pro)

- **TensorFlow:** stable 2.21 ships cp312/cp313 wheels only; only `tf-nightly` 2.22.0.dev publishes cp314 ([PyPI tensorflow](https://pypi.org/project/tensorflow), [tf-nightly cp314](https://pypi.org/project/tf-nightly/2.22.0.dev20260725/)). So the original `crepe` package, SPICE, and Basic Pitch's TF backend are **out** on 3.14 unless mama gets a 3.13 venv.
- **PyTorch:** official cp314 wheels since 2.9/2.10 and retained through 2.15 ([PyTorch dev-discuss notice](https://dev-discuss.pytorch.org/t/notice-python-3-10-support-is-being-removed-from-pytorch-2-15-2-14-is-the-last-release-with-3-10-wheels/3440)). `torchcrepe` and `penn` therefore work; MPS acceleration is a bonus, but CREPE-tiny on CPU is fine for seconds-long clips.
- **ONNX Runtime:** 3.14 support from 1.24.1 ([release notes](https://newreleases.io/project/pypi/onnxruntime/release/1.24.1)); the `onnx` package itself lagged, so Basic Pitch's ONNX extra may need pinning.
- **numba** (librosa dependency): 3.14 from 0.63.0, current 0.68 ships cp314 ([numba announcement](https://numba.discourse.group/t/ann-numba-0-63-1-and-llvmlite-0-46-0/3092)). librosa 0.11 is pure Python and distro-packaged for 3.14 (Arch, Gentoo) but has no explicit 3.14 classifier — treat as "works, unconfirmed by upstream".
- **madmom** (the other common onset/beat library): PyPI 0.16.1, long-standing numpy pins and missing wheels for even 3.8–3.10 ([madmom issues](https://github.com/cpjku/madmom)); **avoid** on 3.14.
- **Basic Pitch:** published support stops at 3.11 (3.10 on Apple silicon). Running it on mama means a side venv (3.10/3.11 via `uv`/pyenv) or the CoreML model loaded directly through `coremltools`. Decide at prototype time; it is not load-bearing for v1.

Recommendation: a **Python 3.13 or 3.12 venv on mama** for the audio-ML tools sidesteps every caveat above; the "ML on mama" job runner (map's "Remote ML job shape" item) should not assume the system 3.14.

## 2. Beatbox / mouth-drum → drum hits

### 2.1 Structure of the problem

The literature calls this **vocal percussion transcription (VPT)** and uniformly uses *segment-and-classify*: onset detection → per-hit feature/embedding → classifier over a small label set (kick, snare, closed hat, open hat). There is no off-the-shelf "beatbox-to-MIDI" pretrained package; there are datasets, papers, and one research repo.

### 2.2 Datasets and prior art

| Resource | Content | Why it matters |
|---|---|---|
| **AVP — Amateur Vocal Percussion dataset** ([Delgado et al. 2020](https://arxiv.org/abs/2009.11737); [Zenodo v4, CC BY 4.0, 231 MB](https://zenodo.org/records/5036529)) | 9,780 utterances, 28 participants with little/no beatboxing experience, **MacBook Pro built-in mic, indoors**; classes kd/sd/hhc/hho with onset + label CSVs, plus onset/coda phoneme labels; "personal" and "fixed" imitation modes and a free improvisation per participant | Closest match to our musician: amateur, laptop mic, four classes. Baseline experiments in the paper are onset detection only (four algorithms compared) |
| **LVT — Live Vocalised Transcription** ([Ramires, Penha, Davies 2018](https://arxiv.org/abs/1811.02406)) | 20 participants (11 m / 9 f), each one fixed loop imitation + one improvisation; three mics; classes kd/sd/hhc. Delivered as a **Max for Live device** using kNN with user-specific sequential forward feature selection | Shows the design we should copy: tiny per-user training set, kNN, feature selection per user |
| **Deep embeddings for user-based VPT** ([Delgado et al., SMC 2022](https://arxiv.org/abs/2204.04646); [code, Apache-2.0](https://github.com/alejandrodl/vocal-percussion-transcription)) | CNN trained on AVP+LVT with syllable-level labels → embeddings → **kNN per user** | Best user-based result **0.899 ± 0.025** participant-wise accuracy; engineered-timbre baseline 0.840; feature-selection baseline 0.827; user-agnostic HMM speech recogniser **0.725**. Spectrogram front end: 64×48 log-mel, 23 ms frame, 8 ms hop. Pretrained weights are referenced ("`cnn_syllable_level_original.h5`") but the README link is a placeholder; Keras `.h5` → TF dependency again |
| **Query by vocal percussion** ([Delgado et al. 2021](https://arxiv.org/abs/2110.09223)) | Comparative study of classic ML vs deep models and augmentations for matching a vocal hit to a drum *sample* | This is the FETCH-adjacent variant: use the musician's "pff" to pick a kick sample from a local library, not just a class label |
| **Stowell & Plumbley 2010**, "Delayed decision-making in real-time beatbox percussion classification", *JNMR* 39(3) ([record](https://openresearch.surrey.ac.uk/esploro/outputs/journalArticle/Delayed-Decision-making-in-Real-time-Beatbox-Percussion/99516386102346)) | Experienced beatboxers (14, 7,460 utterances), varied mics/noise, some polyphonic events (kick + open hat) | Key live-mode finding: classifying from a frame that starts **~23 ms after** the onset beats classifying from the transient itself — low-latency live VPT must accept a ~25–50 ms decision delay |
| Sinyor et al., ISMIR 2005 ([pdf](https://archives.ismir.net/ismir2005/paper/000126.pdf)) | 5 unvoiced drum types, AdaBoost/C4.5 | ~95.6% on a single-performer set; confirms the task is easy *per performer* with handcrafted features |

### 2.3 Accuracy expectations

- **Per-musician, four classes, ~20–50 labelled examples each:** 85–90% is the published ceiling for amateurs (0.899 with deep embeddings; 0.84 with plain timbre features + kNN — the latter has no TF dependency and is what I'd prototype first).
- **Zero-shot / user-agnostic:** ~0.73 and falls off badly across people because everyone's "ts" and "pff" differ. Don't ship this.
- **Onset detection** on dry vocal percussion is the easy part: vocal hits are sharp and sparse; `librosa.onset.onset_detect` (spectral-flux envelope, peak picking, `backtrack=True` to land on the energy minimum before the hit) is sufficient with a dry mic. Open-hat vs closed-hat is the usual confusion (duration of the "tss" tail). Kick vs snare confusion mostly comes from the musician being inconsistent, which is why a quick per-session calibration ("give me four kicks, four snares, four hats") is in the recommended pipeline.

### 2.4 Where it runs

The onset + handcrafted-feature + kNN pipeline is cheap enough for the **laptop CPU** (librosa + scikit-learn), which matters for any future live mode. The CNN-embedding variant lives on mama. Everything here is in the few-hundred-millisecond range for a 4-bar take, dominated by STFT, not the classifier.

## 3. Tempo and feel from a vocal groove

- **Tempo:** `librosa.beat.beat_track` ([doc](https://librosa.org/doc/0.11.0/generated/librosa.beat.beat_track.html)), Ellis's dynamic-programming beat tracker (*JNMR* 36(1), 2007), returns `(tempo, beats)`; seed with `start_bpm`, and pass `bpm=` to skip estimation entirely when the musician used a click. Caveats: on a sparse unaccompanied vocal groove it commonly halves/doubles the tempo and locks to the kick pattern rather than the pulse; returns 0 BPM and no beats if no onset strength is found.
- **Feel:** once the grid is known (ideally from the click, else from `beat_track`), *feel* is simply the signed offset of each detected onset from its nearest grid subdivision (swing ratio from the 8th-note offsets, push/pull per drum class). This is pure numpy on the onset list; no model exists or is needed. Preserve the unquantised onset times in the motif so WRITE can apply the groove as a Logic groove template later rather than hard-quantising.
- **Metre:** none of the above detects 3/4 vs 4/4 reliably from eight hits. Ask the musician (or default to the session's time signature, which the MCU limb can read back).

## 4. Live vs record-then-process

### 4.1 Capture on the laptop

`sounddevice` ([streams doc](https://python-sounddevice.readthedocs.io/en/latest/api/streams.html)) wraps PortAudio, which uses CoreAudio on macOS:

- `InputStream(callback=…)` delivers `indata` blocks on a high-priority thread; the callback must not allocate, touch the file system, or block — push into a ring buffer/queue, process elsewhere.
- `latency='low'|'high'|seconds` selects the device's `default_low_input_latency` ("for interactive performance") or `default_high_input_latency` ("robust non-interactive"); `blocksize=0` lets PortAudio pick an optimal, possibly varying block size; a fixed blocksize "may introduce an additional layer of buffering". `Stream.latency` reports the real figure and "may differ significantly" from what was requested.
- The same laptop is running Logic; a second CoreAudio client on the same interface is normal. Alternative: have Logic record the take and read the file (reuses the audio-tap/`AUNetSend` work in #4 and keeps the audio in the session as provenance).

### 4.2 Latency budget for a live mode

| Stage | Inherent |
|---|---|
| Audio I/O block (CoreAudio, 128–256 frames @ 48 kHz) | 3–6 ms + driver |
| CREPE window | 64 ms (needs 32 ms look-ahead around the frame centre) |
| pYIN frame (2048 @ 22.05 kHz) | 93 ms |
| Onset detection + "delayed decision" classification | ~23 ms after onset (Stowell) + one STFT hop |
| Note segmentation (must see the note end) | the note length |
| Round trip to mama over LAN | single-digit ms + model warm start |

So a live melody follower is ~100 ms behind the voice, and a live drum transcriber ~50 ms — both fine for *display and accumulation*, neither fast enough for the agent to **play along** sample-accurately without prediction. What live turn-taking actually needs beyond v1:

1. **Streaming frontends** — per-frame pitch (torchcrepe/penn accept chunks) and online onset detection on a ring buffer; Viterbi/backtracking become windowed.
2. **Turn boundaries** — a silence timeout, a hotkey, or a spoken cue ("okay") to say the motif is complete; otherwise the agent cannot know when to respond. This is interface design (stage 5) as much as DSP.
3. **Where the model runs** — CREPE-tiny or pyin on the laptop CPU is plausible for one voice; the CNN-embedding beatbox model would stream frames to mama. Measure before choosing.
4. **Click/transport sync** — the live grid must come from Logic's transport (MCU timecode stream, #3) so the agent's response lands on the bar line.

None of this is needed to get value from Vocalizations; the recorded path gets 90% of the motif with 10% of the engineering.

## 5. What the musician must do for good results

- **Count-in on a click**, and record the click only in headphones, never in the room — it would otherwise be detected as hats. With a click the grid is known, and tempo estimation is skipped (`bpm=` to `beat_track`).
- **One idea per take, 2–8 bars.** Separate the melody hum and the beatbox into separate takes; a mixed take forces source separation (#17's territory) and halves accuracy.
- **Dry, close mic, quiet room.** The AVP dataset was recorded on a MacBook built-in mic indoors and still trained to ~0.9, so a laptop mic is acceptable; a USB/interface mic is better. Room reverb smears onsets and open-hat tails.
- **Articulate melodies on a syllable ("da", "doo")** if they want clean note boundaries; hum smoothly if they want the gliding contour kept.
- **Per-session calibration for drums:** four to eight examples of each sound they intend to use. This 20-second ritual is what moves accuracy from ~0.73 to ~0.9.
- **Say the intended instrument/octave** (or let the agent ask) — the pitch tracker reports what was sung, not what was meant.

## 6. Recommended v1 pipeline (recorded input)

```
laptop                                   mama (ssh, Python 3.12/3.13 venv)
──────                                   ───────────────────────────────────
record take (Logic or sounddevice)  ──►  vocal-motif <take.wav> --kind melody|drums --bpm N --calib calib/
  + metadata: bpm, time sig, kind         ├─ melody: torchcrepe(full, hop 10 ms) → periodicity threshold
                                          │           → median filter → note segmentation → quantise to grid
                                          │           → MIDI + f0 curve + per-note confidence
                                          └─ drums:  librosa onset_detect(backtrack) → per-hit 23 ms-delayed
                                                      log-mel/MFCC features → kNN vs this session's calib
                                                      → class + confidence; beat_track or --bpm for grid
                                                      → MIDI (GM drum notes) + raw onset times (feel)
                                   ◄──   motif.json + motif.mid (provenance: wav path, model, version)
```

- CLI tool + skill doc, per the pi convention. Output is a motif with provenance, feeding the MIDI-write limb.
- Keep `librosa.pyin` as a fallback when torch is unavailable; keep Logic's Flex-Pitch→MIDI as the no-ML fallback for melody via UI scripting.
- Confidence below threshold → the agent asks ("was that a snare or a rimshot?") rather than guesses; this is the LISTEN-side of the traceability rule.

## 7. Open questions for the prototype

1. Does CREPE-full on the M2 Pro CPU/MPS process an 8-bar take in < 2 s? (Expected yes.)
2. Plain MFCC + kNN vs the AVP deep embeddings on *Margot's* voice — is the TF dependency worth +5 points?
3. Whether Basic Pitch's articulated-note handling beats the f0-segmentation heuristic on "da-da" takes, enough to justify a 3.10 venv or CoreML loading.
4. How the take gets to mama (rsync vs a small HTTP service) — the map's "Remote ML job shape" item; this ticket only requires "WAV in, JSON+MIDI out".

## Sources

- CREPE: [paper](https://arxiv.org/abs/1802.06182), [results table](https://arxiv.org/html/1802.06182v1), [repo](https://github.com/marl/crepe); [torchcrepe](https://github.com/maxrmorrison/torchcrepe); [penn](https://github.com/interactiveaudiolab/penn)
- pYIN: [librosa.pyin](https://librosa.org/doc/0.11.0/generated/librosa.pyin.html) (Mauch & Dixon, ICASSP 2014)
- SPICE: [Gfeller et al. 2020](https://arxiv.org/abs/1910.11664)
- Basic Pitch: [paper](https://arxiv.org/abs/2203.09893), [HTML with datasets](https://arxiv.org/html/2203.09893), [repo](https://github.com/spotify/basic-pitch), [PyPI](https://pypi.org/project/basic-pitch/)
- AVP dataset: [paper](https://arxiv.org/abs/2009.11737), [Zenodo](https://zenodo.org/records/5036529); deep embeddings: [paper](https://arxiv.org/abs/2204.04646), [code](https://github.com/alejandrodl/vocal-percussion-transcription); query by vocal percussion: [paper](https://arxiv.org/abs/2110.09223)
- LVT: [Ramires, Penha, Davies 2018](https://arxiv.org/abs/1811.02406)
- Stowell & Plumbley 2010, JNMR 39(3): [record](https://openresearch.surrey.ac.uk/esploro/outputs/journalArticle/Delayed-Decision-making-in-Real-time-Beatbox-Percussion/99516386102346); Sinyor et al. ISMIR 2005: [pdf](https://archives.ismir.net/ismir2005/paper/000126.pdf)
- librosa onsets/beats: [onset_detect](https://librosa.org/doc/0.11.0/generated/librosa.onset.onset_detect.html), [beat_track](https://librosa.org/doc/0.11.0/generated/librosa.beat.beat_track.html)
- sounddevice: [streams](https://python-sounddevice.readthedocs.io/en/latest/api/streams.html), [checking hardware](https://python-sounddevice.readthedocs.io/en/latest/api/checking-hardware.html)
- Python 3.14 status: [tensorflow on PyPI](https://pypi.org/project/tensorflow), [tf-nightly cp314](https://pypi.org/project/tf-nightly/2.22.0.dev20260725/), [PyTorch notice](https://dev-discuss.pytorch.org/t/notice-python-3-10-support-is-being-removed-from-pytorch-2-15-2-14-is-the-last-release-with-3-10-wheels/3440), [onnxruntime 1.24.1](https://newreleases.io/project/pypi/onnxruntime/release/1.24.1), [numba 0.63.1](https://numba.discourse.group/t/ann-numba-0-63-1-and-llvmlite-0-46-0/3092), [madmom](https://github.com/cpjku/madmom)
- Logic Flex Pitch → MIDI: [Apple support guide](https://support.apple.com/guide/logicpro/lgcpe2fd1b83/mac)
