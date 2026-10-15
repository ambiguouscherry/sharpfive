# Research: stem separation and transcription models — quality and runtime on mama vs AWS

Resolves issue #17. Researched 2026-10-10/11 against PyPI release metadata, the upstream repos/papers, and **measured runs on mama** (Mac mini M2 Pro, 16 GB, macOS 27.0, Python 3.14.7, Homebrew `uv`). Every model below was installed into a fresh `uv` venv on mama and timed on a synthetic 4-minute 44.1 kHz stereo track (`test240.wav`: saw bass, stepped melody, noise-burst drums at 120 BPM, a vibrato "vocal") plus a 30-second mono "hum" excerpt. No ffmpeg was needed for any of it.

## TL;DR / Recommendation

| Task | Default | Fallback / upgrade | 4-min track on mama |
|---|---|---|---|
| **Stems (4)** | `demucs==4.1.0`, model `htdemucs`, `-d mps` | `htdemucs_ft` when quality matters more than 4x runtime; `audio-separator` + BS-RoFormer for a best-possible *vocal/instrumental* split | **~16–19 s** (MPS), ~59 s (CPU); `htdemucs_ft` **71 s** (MPS) |
| **Stems (6, +guitar/piano)** | `htdemucs_6s` | — (upstream says piano "is not working great") | **22 s** (MPS) |
| **Polyphonic transcription → MIDI** | `basic-pitch==0.4.0` on its bundled ONNX model via `onnxruntime` (install `--no-deps`, see recipe) | none open-source at this weight class; run on a Demucs stem, not the mix | **4.7 s** (CPU) |
| **Monophonic hum / voice f0** | `torchcrepe==0.0.24` `full` model, 5 ms hop, periodicity-thresholded | `librosa.pyin` (no weights, no torch) | **~1 s / 30 s audio** (CPU or MPS) vs pyin 5.2 s / 30 s |
| **Drums → MIDI** | `adtof-pytorch` (ADTOF weights, 5-class) run on the Demucs `drums` stem | none comparable in the open; licence is non-commercial (see §6) | **2.8 s** (CPU) |
| **Tempo / beats / key** | `librosa==1.0.0` beat_track + `essentia` RhythmExtractor2013/KeyExtractor (both pure-wheel, no weights) | `madmom` from git (better beat/downbeat; CC BY-NC-SA models) | librosa 4.6 s, essentia 2.4 s, madmom 18 s |
| **Sections (verse/chorus)** | **No ready default.** `allin1` imports fail against current NATTEN; see §5 | treat as open; candidate: pin NATTEN 0.14.x from source, or own segmentation on Demucs stems + madmom downbeats | — |
| **AWS overflow** | not needed for single tracks — mama's MPS beats a T4 for this workload class. For batch/ensemble jobs: **g6.xlarge** (L4 24 GB, ~$0.81/h) or **g4dn.xlarge** spot (~$0.29/h) | | |

**Key finding on the "torch on Python 3.14" question:** it is a non-issue as of 2026-10. `torch==2.14.1` and `torchaudio==2.11.0` publish `cp314` macOS arm64 wheels on PyPI; MPS is available; Demucs 4.1.0 (July 2026, packaging overhaul) installs and runs on 3.14 with nothing but `uv pip install`. The casualties on 3.14 are the **TensorFlow-based** candidates: Spleeter (pins `tensorflow==2.12.1`, `python<3.12`) is dead, and Basic Pitch's *default* install path is broken (its macOS dependency marker selects `tensorflow-macos`/`coremltools`, neither of which has cp314 wheels) — but its bundled ONNX model runs fine on `onnxruntime` 1.31, which does ship cp314 wheels.

## 1. Environment facts (mama, verified over ssh)

- macOS 27.0 (26A428), Apple M2 Pro, 16 GB, 327 GB free. Python 3.14.7 (Homebrew), `uv` installed, **no ffmpeg, no torch** before this work.
- `uv venv` creates venvs **without pip** — use `uv pip install --python <venv>/bin/python ...` (or `python -m ensurepip`).
- Python 3.14 venvs also ship **no `setuptools`**, and current `setuptools` (84.0) **no longer contains `pkg_resources`**. Anything that imports `pkg_resources` (resampy ≤0.4.2) breaks; pin `resampy==0.4.3`.

## 2. Stem separation

### 2.1 Demucs (recommended)

- **Release state.** `demucs==4.1.0` on PyPI, uploaded 2026-07-11 by Alexandre Défossez (`adefossez/demucs` is the officially maintained repo now that he has left Meta; "expect slow replies and no new feature"). Requires Python ≥3.10, torch ≥2.1. The 4.1.0 release notes: `pyproject.toml`/hatchling packaging; **inference no longer uses torchaudio** (decoding via `sphn`, ffmpeg fallback, ffmpeg needed only for FLAC output); Wiener filter vendored (no openunmix dep); checkpoints load with `weights_only=False` on torch ≥2.6; **pretrained weights now hosted on the HuggingFace hub as safetensors** (`hf://[namespace/]name` forces hub loading); new `Separator` API (`demucs/api.py`) and `--other-method {add,minus,none}` for `--two-stems`. ([release notes](https://github.com/adefossez/demucs/blob/main/docs/release.md))
- **MPS support is real but partial, by design.** `separate.py` defaults `-d` to `cuda` → `mps` → `cpu`. `spec.py` moves tensors to CPU for `th.stft`/`th.istft` when the device is `mps`/`xpu` (complex ops on CPU, added in 4.0.1: "Complex-number computations run on the CPU when using the MPS device"); `htdemucs.py`/`hdemucs.py` do the same around their spectral branches. So an MPS run is a hybrid, which is why `user` CPU time on MPS runs is non-trivial. It works: no `PYTORCH_ENABLE_MPS_FALLBACK` needed.
- **Quality (upstream numbers, MUSDB HQ test, SDR "all" in dB):** Hybrid Demucs v3 7.7; **HT Demucs fine-tuned (v4, `htdemucs_ft`) 9.0** with 800 extra training songs; 9.20 with sparse attention (paper only, not shipped). README: `htdemucs_ft` "might be a bit better" at 4x the runtime; `htdemucs_6s` adds piano+guitar, piano "not working great at the moment". ([README](https://github.com/adefossez/demucs), [Rouard, Massa, Défossez 2022, arXiv:2211.08553](https://arxiv.org/abs/2211.08553)) MVSep's independent Multisong leaderboard puts `htdemucs_ft` at vocals 8.33 / bass 12.05 / drums 11.24 / other 5.74 SDR, vs plain `htdemucs` 8.18 / 11.74 / 10.90 / 5.57 — i.e. the fine-tune buys ~0.2–0.3 dB. ([mvsep.com/algorithms](https://mvsep.com/en/algorithms))
- **Measured on mama (4-min stereo track; wall clock, includes Python start-up and writing four WAVs):**

  | Run | Wall | Notes |
  |---|---|---|
  | `htdemucs` MPS, first run | 19.4 s | includes ~80 MB weight download |
  | `htdemucs` MPS, rerun | ~16 s | by output mtime; weights cached |
  | `htdemucs --two-stems vocals` MPS | ~16 s | same model; only output differs |
  | `htdemucs` CPU, first run | 67 s | includes download; `user` 3m40s (all cores) |
  | `htdemucs` CPU, rerun | ~59 s | ≈ 0.25× realtime (README says ~1.5× on a generic CPU) |
  | `htdemucs_ft` MPS, first run | 71 s | includes ~320 MB download; ≈ 4× `htdemucs`, as documented |
  | `htdemucs_6s` MPS, first run | 22 s | |

  RAM was never an issue at 16 GB (README's "7 GB GPU" guidance is for CUDA; MPS shares system memory). Default `--segment` and `--shifts 1` were used; `--shifts` multiplies runtime linearly.
- **Licence:** MIT (code and weights, same repo).

### 2.2 Spleeter — not viable

`spleeter==2.4.2` (2025-04) pins `tensorflow==2.12.1`, `numpy<2`, `python<3.12`. TensorFlow 2.21 has no cp314 wheel at all, and `tensorflow-macos` stopped at 2.16.2 (cp39–cp312). Quality is also a generation behind (2019 U-Net). Drop it.

### 2.3 "MVSep-style" ensembles / RoFormers

- The state of the art for **vocal/instrumental** is BS-RoFormer / Mel-Band RoFormer (MVSep Multisong: BS-RoFormer 2025.07 vocals 11.89 SDR vs `htdemucs_ft` 8.33; their 2025.06 five-stem ensemble reaches vocals 11.93 / bass 14.85 / drums 14.33 / other 9.00). Many of MVSep's own ensemble weights are site-only; the open ones are reachable through **`audio-separator`** (MIT, `pip install "audio-separator[cpu]"`, Python ≥3.10 except 3.14.1, needs torch ≥2.13; uses MPS for `.ckpt` models and CoreML for `.onnx`; default model `model_bs_roformer_ep_317_sdr_12.9755`). Weights come from the UVR community with mixed/unspecified licences — check per model before shipping. ([python-audio-separator README](https://github.com/nomadkaraoke/python-audio-separator), [mvsep.com/algorithms](https://mvsep.com/en/algorithms))
- Not installed or timed here (90-minute budget). RoFormers are several times heavier than HTDemucs; this is the workload that would justify the AWS GPU (§7). Recommendation: Demucs by default; add `audio-separator` later only for a "best vocal" path.

## 3. Polyphonic transcription — Basic Pitch

- Spotify's instrument-agnostic note transcription (Bittner et al., [arXiv:2203.09893](https://arxiv.org/abs/2203.09893), ICASSP 2022). Apache-2.0. Ships four serialisations of the same model (TF SavedModel, CoreML, TFLite, ONNX) and picks the first importable backend in that order; `--model-serialization` overrides. ([README](https://github.com/spotify/basic-pitch))
- **3.14 install problem.** `basic-pitch==0.4.0` (2024-08, latest) declares `coremltools; platform_system=="Darwin"` and `tensorflow-macos<2.15.1; Darwin and python>3.11`. `coremltools==9.0` has wheels only up to cp313; `tensorflow-macos` only to cp312. A plain `uv pip install basic-pitch` on 3.14 fails resolution (reproduced). Upstream issue [#203](https://github.com/spotify/basic-pitch/issues/203) and PRs [#201](https://github.com/spotify/basic-pitch/pull/201)/[#204](https://github.com/spotify/basic-pitch/pull/204) (fall back to onnxruntime/coremltools on 3.12+) are **open, unmerged** as of 2026-09.
- **Workaround that works:** install `basic-pitch` with `--no-deps`, then its pure-Python deps plus `onnxruntime` (1.31.0 ships cp314 arm64 wheels). `ICASSP_2022_MODEL_PATH` then resolves to the bundled `saved_models/icassp_2022/nmp.onnx` automatically (verified). PR #204's author reports ONNX output within rounding of the TF baseline.
- **Measured:** 240 s stereo track → 856 note events in **4.7 s** wall on CPU (onnxruntime; nothing on the GPU). It is effectively free.
- **Quality note:** no absolute benchmark numbers in README/abstract ("substantially better than a comparable baseline" for notes; frame accuracy "only marginally below" specialised AMT). Expect usable sketches on a single-instrument stem, mush on a full mix — always transcribe a Demucs stem.

## 4. Monophonic pitch — CREPE vs pyin

- **`torchcrepe==0.0.24`** (MIT, pure-Python wheel; depends on torch/torchaudio/librosa/resampy). Pins nothing problematic. Outputs f0 + periodicity; has `filter.median`, `threshold.At(0.21)`, `threshold.Hysteresis`, `threshold.Silence` utilities for cleaning hum tracks. CREPE's paper claims equal-or-better than pYIN on monophonic audio; independent singing-voice evaluations find them close. ([torchcrepe README](https://github.com/maxrmorrison/torchcrepe), [Kim et al. 2018, arXiv:1802.06182](https://arxiv.org/abs/1802.06182))
- **Measured, 30 s hum, 5 ms hop (6 076 frames), `full` model:** 0.90 s CPU, 0.65 s MPS. *Correction 2026-10-15 (#38, measured on real takes):* these figures are wrong by an order of magnitude — `full` costs **~0.6 s of model time per audio second at a 10 ms hop on MPS** (double at 5 ms) and **CPU is ~15× slower than MPS** (117 s for 8 s of audio); `tiny` is 7× faster than `full` but invents scoop notes. Still seconds for a 2–8-bar take, so the recommendation stands; see `prototype/hear-transcribe/README.md`. `librosa.pyin` on the same clip: 5.2 s (single-core numba). Both are fast enough; CREPE is both faster and the better-documented quality, so it is the default; pyin stays as the zero-weights fallback.
- The `crepe` (TF) package is sdist-only and TF-bound — skip it.
- Caveat on my check signal: its vibrato was generated as `sin(2π·f(t)·t)` rather than from integrated phase, so its true instantaneous frequency swings far wider than intended; the f0 medians from this run say nothing about accuracy. Use a real humming recording for a quality check.

## 5. Drums, tempo, key, sections

- **Drum transcription — ADTOF.** Zehren et al., ISMIR 2021 / *Signals* 2023; 359 h of annotated non-synthetic music; 5-class output (the training data limits it to 5 classes). The original is Keras/TF+madmom (Python 3.10). The maintained route is **[xavriley/ADTOF-pytorch](https://github.com/xavriley/ADTOF-pytorch)**, linked from the official README: torch+librosa+pretty_midi only, bundled weights, CLI `adtof --audio in.wav --out out.mid`, F-measure 88.51 vs original 88.74 on MDBDrums++. Installed from git on 3.14 without incident; **2.8 s** on the 4-min Demucs drums stem (85 hits detected on the synthetic noise-burst "kit"). ([ADTOF README](https://github.com/MZehren/ADTOF))
- **Tempo / beats / key.**
  - `librosa==1.0.0` (ISC, requires Python ≥3.12, pure wheel; numba 0.68 has cp314 wheels): `beat_track` → 120.19 BPM, 479 beats in 4.6 s including load. Fine for tempo; its key estimation is DIY (chroma + templates).
  - `essentia==2.1b6.dev1438` (2026-05) ships a **cp314 macOS 15 arm64 wheel** and imports on macOS 27. `RhythmExtractor2013(multifeature)` + `KeyExtractor` on the 4-min track: 2.4 s total (118.2 BPM, 479 beats; key output on the synthetic signal is meaningless). Licence: **AGPLv3** for non-commercial use, commercial licence from UPF; its TensorFlow models are CC BY-NC-ND (not used here). ([essentia licensing](https://essentia.upf.edu/licensing_information.html), [RhythmExtractor2013](https://essentia.upf.edu/reference/std_RhythmExtractor2013.html))
  - `madmom`: PyPI release 0.16.1 is from 2018 (sdist, breaks on numpy 2 via `np.float`). **`pip install git+https://github.com/CPJKU/madmom`** (0.17.dev0) builds its Cython extensions on 3.14 and runs: RNN beat activation + DBN tracking + CNN key on 4 min = 18.4 s (120.0 BPM, 481 beats). Code BSD, **models CC BY-NC-SA 4.0** (commercial use needs Gerhard Widmer's consent). Best-in-class classical beat/downbeat; use when librosa's beat grid wobbles.
- **Sections — allin1 (Kim & Nam, WASPAA 2023).** Outputs BPM, beats, downbeats and labelled segments (intro/verse/chorus/bridge/…) from Demucs stems; MIT. `allin1==1.1.0` (2023-10, repo last pushed 2024-05) installed on 3.14 with torch 2.14, NATTEN 0.21.7 (built from sdist, ~10 s) and madmom-from-git — but **`import allin1` fails**: `cannot import name 'natten1dav' from 'natten.functional'`. NATTEN removed that API; allin1 was never updated. Fixing it means pinning NATTEN ≤0.14.x and building that from source against torch 2.14 (untested, probably painful) or vendoring allin1's model with current NATTEN calls. Treat structure detection as **open**; the cheap interim is madmom/essentia downbeats plus novelty-based segmentation on the Demucs stems.

## 6. Licensing summary

| Component | Code | Weights/models | OK for a shipped product? |
|---|---|---|---|
| Demucs 4.1.0 | MIT | MIT | yes |
| Basic Pitch | Apache-2.0 | Apache-2.0 | yes |
| torchcrepe | MIT | MIT (CREPE) | yes |
| librosa / numba / onnxruntime / torch | ISC / BSD / MIT / BSD | — | yes |
| essentia | AGPLv3 (non-commercial) or paid | CC BY-NC-ND (TF models) | **no** without a UPF licence; fine for personal/research use |
| madmom | BSD | **CC BY-NC-SA 4.0** | personal use fine; commercial needs consent |
| ADTOF / ADTOF-pytorch | CC BY-NC-SA 4.0 / no licence file (weights derived from ADTOF) | non-commercial | personal use fine |
| audio-separator | MIT | per-model, often unspecified (UVR community) | check per model |
| allin1 | MIT | MIT, but depends on madmom models | inherits madmom's NC |

sharpfive is a personal producer-agent today, so none of this blocks; the NC items are flagged for the day it isn't.

## 7. mama vs AWS

- **mama is sufficient for everything in the default column.** A full 4-stem separation of a 4-minute track is ~16 s on MPS, transcription and analysis passes are seconds. Even `htdemucs_ft` at ~70 s is "go make coffee", not "queue it". The 16 GB is not a constraint for these models.
- **When AWS makes sense:** RoFormer ensembles via `audio-separator`, batch jobs over a library, or anything that needs CUDA-only kernels (NATTEN's fused ops, flash-attention). On-demand Linux us-east-1 (third-party mirrors of the AWS price list, checked 2026-10): **g4dn.xlarge** T4 16 GB, 4 vCPU/16 GB — $0.526/h (spot ~$0.29); **g6.xlarge** L4 24 GB — $0.805/h (spot ~$0.60); **g5.xlarge** A10G 24 GB — $1.006/h (spot ~$0.47). Recommendation: g6.xlarge on demand for predictable runs, g4dn.xlarge spot for cheap batch. ([instances.vantage.sh g4dn.xlarge](https://instances.vantage.sh/aws/ec2/g4dn.xlarge), [g6.xlarge](https://instances.vantage.sh/aws/ec2/g6.xlarge), [g5.xlarge](https://instances.vantage.sh/aws/ec2/g5.xlarge)) At $0.81/h, one hour of L4 buys ~200 `htdemucs` separations — the break-even argument for a persistent cloud box doesn't exist for a single user.
- Same `uv` recipe works on Linux with the CUDA torch wheel; Demucs then runs fully on GPU (no CPU STFT hop).

## 8. Pinned install recipe (verified on mama, Python 3.14.7, 2026-10-11)

```sh
# one venv for stems + transcription + analysis
uv venv --python 3.14 ~/.venvs/sharpfive-listen
P=~/.venvs/sharpfive-listen/bin/python

# core (cp314 arm64 wheels exist for all of these)
uv pip install --python $P \
  "torch==2.14.1" "torchaudio==2.11.0" \
  "demucs==4.1.0" numpy soundfile \
  "librosa==1.0.0" "torchcrepe==0.0.24" "resampy==0.4.3" \
  "essentia==2.1b6.dev1438" "onnxruntime==1.31.0"

# Basic Pitch: bypass its TF/coremltools markers, use the bundled ONNX model
uv pip install --python $P --no-deps "basic-pitch==0.4.0"
uv pip install --python $P mir_eval pretty_midi scikit-learn typing-extensions

# optional, non-commercial licences (see §6)
uv pip install --python $P cython "git+https://github.com/CPJKU/madmom"      # 0.17.dev0
uv pip install --python $P "git+https://github.com/xavriley/ADTOF-pytorch"   # adtof CLI

# usage
demucs -d mps -n htdemucs -o stems/ track.wav              # ~16 s per 4-min track
demucs -d mps -n htdemucs --two-stems vocals -o stems/ track.wav
basic-pitch out/ stems/htdemucs/track/other.wav             # auto-picks nmp.onnx
adtof --audio stems/htdemucs/track/drums.wav --out drums.mid --device cpu
```

Gotchas captured above: no pip/setuptools in `uv` venvs; `pkg_resources` is gone (hence `resampy==0.4.3`); Demucs weights land in `~/.cache/huggingface` (454 MB for htdemucs+ft+6s); first run of each model downloads.

## 9. What was left on mama

Everything is under `~/sharpfive-ml-research/` (three venvs ≈ 2.9 GB, test signals and stem outputs ≈ 1.5 GB) plus `~/.cache/huggingface` (454 MB, Demucs weights — worth keeping) and `~/.cache/uv` (2.1 GB wheel cache). Nothing was installed into the system Python; no ffmpeg was installed. Delete `~/sharpfive-ml-research` when the real venv exists.

## Sources

- PyPI JSON metadata (wheel tags, `requires_python`, upload dates) for torch, torchaudio, demucs, spleeter, basic-pitch, crepe, torchcrepe, librosa, madmom, essentia, allin1, onnxruntime, tensorflow(-macos/-metal), numpy, numba, coremltools, resampy, audio-separator, NATTEN — primary
- Measured runs on mama via ssh, 2026-10-10/11 — primary
- [adefossez/demucs](https://github.com/adefossez/demucs) README and `docs/release.md`; installed `demucs/spec.py`, `separate.py` (MPS handling) — primary
- [Rouard, Massa, Défossez — Hybrid Transformers for Music Source Separation, arXiv:2211.08553](https://arxiv.org/abs/2211.08553)
- [MVSep algorithms/leaderboard](https://mvsep.com/en/algorithms) — independent SDR tables
- [spotify/basic-pitch](https://github.com/spotify/basic-pitch) README, issue #203, PRs #201/#204; [Bittner et al., arXiv:2203.09893](https://arxiv.org/abs/2203.09893)
- [maxrmorrison/torchcrepe](https://github.com/maxrmorrison/torchcrepe); [Kim et al. CREPE, arXiv:1802.06182](https://arxiv.org/abs/1802.06182); [librosa.pyin docs](https://librosa.org/doc/latest/generated/librosa.pyin.html)
- [MZehren/ADTOF](https://github.com/MZehren/ADTOF), [xavriley/ADTOF-pytorch](https://github.com/xavriley/ADTOF-pytorch) README + `pyproject.toml`
- [CPJKU/madmom](https://github.com/CPJKU/madmom) README (licensing); [mir-aidj/all-in-one](https://github.com/mir-aidj/all-in-one) README; [SHI-Labs/NATTEN](https://github.com/SHI-Labs/NATTEN)
- [Essentia licensing](https://essentia.upf.edu/licensing_information.html), [RhythmExtractor2013 reference](https://essentia.upf.edu/reference/std_RhythmExtractor2013.html)
- [nomadkaraoke/python-audio-separator](https://github.com/nomadkaraoke/python-audio-separator) README
- EC2 prices: [instances.vantage.sh](https://instances.vantage.sh/aws/ec2/g6.xlarge) (mirror of the AWS price list; the AWS pricing page renders client-side and could not be read directly)
