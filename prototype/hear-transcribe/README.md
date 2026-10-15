# Prototype: `sf hear transcribe` — a hummed take on mama becomes a MIDI motif

Resolves issue #38. Built and measured 2026-10-15 with Margot humming (HITL). Laptop: Intel MacBook Pro, built-in mic, 48 kHz. ML box: mama (M2 Pro, Python 3.14, `~/sharpfive-ml-research/.venv-mir` from #17). Model: `torchcrepe==0.0.24` `full` on MPS.

## Answer

**Yes, the LISTEN deep path works end to end in the spec's reply shape, and the remote job shape is settled: ssh + scp, no service.** A 12.4 s take (4-beat count-in + 10 s) round-trips in **~11 s**; the model is ~7.5 s of that. By ear, after one session of tuning on two takes of SWV's "Rain", Margot's verdict on the final MIDI was *"pretty accurate … close enough"*, with the remaining errors all at **semitone boundaries** (notes sung 40–50 cents between two pitches) — key-aware or motif-aware snapping is the step that would "take it to the finish line" (#45). Confidence tracks the errors: every wrong or missing note scored 0.25–0.5, the clean held notes 0.8–0.96.

## What's here

| File | Role |
|---|---|
| `record.swift` → `record` | laptop `hear record`: count-in click to the headphones, then the take from the default mic to WAV. Prints `{file, seconds, sr, bpm, countin_beats, grid_start_s}`. |
| `hear-transcribe.sh` | laptop `hear transcribe`: scp the WAV + script to `mama:~/sharpfive-hear/`, run, scp the motif back, print the reply with local paths and a `round_trip_s` breakdown. |
| `transcribe_mama.py` | the mama side: torchcrepe → periodicity gate → note segmentation → cleanup → MIDI (`pretty_midi`) + its `.motif.json` sidecar (parent = the take), raw f0 CSV, sine rendering for the ear check, one JSON reply. |
| `takes/*.reply.json`, `takes/*.wav.motif.json` | the replies and the take sidecars (root motifs, `source: mic`) for Margot's two takes, final tuning. The WAVs and renderings are her voice and stay untracked. |

Run: `./record takes/take.wav --seconds 10 --bpm 100 --countin 4` (musician runs it, so the count-in starts when they're ready), then `./hear-transcribe.sh takes/take.wav --bpm 100 --grid-start 2.4`, then `afplay out/take/take.render.wav` for the ear check.

## Reply shape (as specced, §3 hear + motif lifecycle)

```json
{"status": "done",
 "motif": {"id": "01M50W360TYEZBYB9XQDNJS8A2", "name": "take2", "path": ".../out/take2/take2.mid", "kind": "midi",
           "parents": ["01M50W2W8JN6EK8S9JM7NMQ5G7"],
           "provenance": {"source": ".../takes/take2.wav",
                          "model": "torchcrepe-full 0.0.24 / torch 2.14.1 / mps on mama",
                          "at": "2026-10-15T15:49:28-07:00"},
           "confidence": 0.575},
 "notes": [{"pitch": 63, "name": "D#4", "cents": -45, "start_s": 2.78, "end_s": 3.12, "confidence": 0.256,
            "beat": 1.633, "offset_ms": -70, "length_beats": 0.567}, ...],
 "raw_notes": [...], "tuning_centre_cents": 0,
 "sidecars": {"motif": ".../take2.mid.motif.json", "f0": ".../take2.f0.csv", "render": ".../take2.render.wav"},
 "audio": {"seconds": 12.4, "sr": 48000, "voiced_seconds": 5.66},
 "timing_s": {"load": 0.751, "infer": 7.575, "total": 8.631},
 "round_trip_s": {"upload": 0.85, "mama": 9.2, "download": 0.55, "total": 10.61}}
```

The take is a root motif (`record` writes `<take>.wav.motif.json`, `source: mic`; the driver makes one for an older take) and the MIDI is its child: `<file>.mid.motif.json` carries id, name, kind, source (`hear`, model, version), parents, at, tempo, bars, confidence, empty `text`, empty `placed` — the sidecar from `spec/motif-lifecycle.md` §3. ids are ULIDs. `notes` is what the MIDI holds; `raw_notes` is the segmentation before cleanup; `beat` / `offset_ms` express the feel against the click grid (the MIDI itself is unquantised, tempo = the click). The f0 CSV keeps the raw curve so pitch-bend can be reconstructed later.

## Measurements

**Synthetic check first** (7-note melody at 100 BPM, 10-cent vibrato, deliberate ±30 ms feel offsets, generated on mama): all 7 pitches right, onsets within ~30 ms of truth, confidence 0.89.

**Timing** (mama, M2 Pro, MPS):

| | |
|---|---|
| `full`, 10 ms hop, 12.4 s take | 7.5 s model, 8.6 s script total (0.7 s load + imports) |
| `full`, 5 ms hop | double: ~1 s per audio second |
| `full` on CPU | ~15× slower than MPS (117 s for 8 s of audio) — never use |
| `tiny`, 10 ms hop | 7× faster than `full` but added a spurious scoop note on the synthetic melody |
| ssh + scp overhead | ~1.7 s (0.85 up, 0.8 down) + ~1 s Python start |

**Correction to `research/stem-separation-and-transcription-models.md` §4:** the "0.65 s MPS / 0.90 s CPU for 30 s of hum" figures there are wrong by an order of magnitude; the real cost is ~0.6 s of model time per audio second at a 10 ms hop on MPS, and CPU is unusable. Still "seconds, not minutes" for a 2–8-bar take, so the conclusion (mama suffices) stands.

**Remote ML job shape** (map fog): a resident service on mama would save only the ~2 s of process start + imports per call. Not worth a daemon; ssh + scp it is. The per-call cost that matters is the model, which scales with take length.

**Takes.** Take 1 was quiet (peak −16 dBFS); take 2 louder (peak −7 dBFS). Louder helped the periodicity but the headline problems were in the script, not the signal.

## What had to change between "runs" and "right by ear"

Eight iterations, each judged by Margot listening to a sine rendering of the MIDI against the song in her head:

1. **torchcrepe's default silence gate (−60 dB A-weighted) zeroed most of a laptop-mic hum** — take 1 kept 2.4 s of 10 s as voiced; at −80 dB it kept 6.8 s. Default is now −80.
2. **Vibrato on a semitone boundary shredded held notes** (one D4/D#4 held note became eight fragments). Segmenter now has hysteresis: a new note needs the 80 ms-smoothed pitch to leave the running median by > 0.8 semitone *and hold for 100 ms*.
3. **Scoops read as notes** (A3 then A#3 where she sang one A#3 from below). A note shorter than 150 ms leading straight into a longer neighbour one semitone away is folded into it; and the pitch is read from the *late* window of the note (40–90 %), not the middle, because singers come in from below.
4. **Repeated same-pitch notes merged** ("didn't catch the eighth notes at the end"). librosa onsets split a run; a 3 dB energy dip-and-rise inside a note also counts (the ending's two G#3s had no detectable onset, only a 3 dB swell). Both halves must be ≥ 130 ms or the split is refused — at 100 BPM anything shorter is a glitch, not an articulation.
5. **Stutters** ("almost glitchy; would need cleaning before MIDI"): a note < 130 ms with confidence < 0.25 is absorbed into the neighbour it touches, pitch and confidence recomputed over the union. The bar was 0.5 first, which also ate a real F3 passing note (conf 0.29) — "there's a note missing from the first two bars". 0.25 keeps it.
6. **Tuning-centre shift** (she sings ~13 cents flat of A440 on average; shift then round) fixed the peak note and broke a passing note — net zero, now off by default (`--tuning-centre` to enable).

## Known limits (the honest list)

- **Semitone-boundary notes are a coin flip.** Take 2's peak sits 45 cents between D4 and D#4 and the two halves of the repeated motif disagree about it. No per-note rule fixes this without breaking another note; the fix is context: snap to the key once a few confident notes establish it, or to the matching note in the repeated motif. → #45.
- **Passing notes vs stutters are the same thing to the model** (short, low periodicity). The 130 ms / 0.25 thresholds are tuned on one singer at one tempo; they should scale with tempo (a 16th at 100 BPM is 150 ms).
- **Legato same-pitch repeats need an audible re-articulation** (≥ 3 dB dip). A pure legato "ooo-ooo" on one pitch comes back as one note; humming "da-da" fixes it at the source.
- **Tempo is given, not detected.** The take is sung to the click the recorder plays; `--bpm` and `--grid-start` come from the recorder's reply. No click → MIDI at 120 with no grid.
- **Latency alignment** between the click playback and the mic file is not measured; onsets landed within ~30 ms on the synthetic check and nothing in the takes suggested worse.
- One singer, two takes, one song. The thresholds are a starting point, not a calibration.
- **Runs are not bit-identical, and boundary notes flip between them.** The same take came back as 23 notes / 0.61 on the run Margot judged and 22 / 0.58 on the regeneration for this write-up: the opening C#4–D#4 pair merged, and the A#3 at beat 3.4 (−27 cents) came back as A3. MPS inference is not deterministic, and a note on the 0.8-semitone or 130 ms edge flips with it. Another argument for #45: context, not thresholds, should decide boundary notes.

## Recorder findings (`hear record`)

- `AVAudioEngine` input tap → `AVAudioFile`, click via `AVAudioPlayerNode` from a pre-rendered buffer, count-in then click through the take. Microphone consent via `AVCaptureDevice.requestAccess(.audio)` was granted from the agent's sandbox without a visible prompt (Ghostty already holds the microphone permission on this machine); a fresh terminal will get the TCC prompt once — that is the `microphone` consent scope from §5.
- **Close the `AVAudioFile` before exit** (set the reference to nil) or the WAV has a zero-length `data` chunk: the header is only finalised on release. First run produced a 143 KB file with 0 readable frames.
- The musician should run `record` themselves (`!` in pi / Claude Code) so the count-in starts when they're ready; the agent running it means the count-in fires at an unpredictable moment.
- Built-in mic reports 48 kHz mono. The pipeline resamples to CREPE's 16 kHz internally; no ffmpeg or sox needed on either machine.
