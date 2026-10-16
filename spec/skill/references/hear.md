# hear: audio in, Motif out

Named, not yet specced: the models are proven in research, the verbs are not. Runs on mama over ssh (`mama` consent). Shape of every reply:

```
{"status":"done","motif":{"id":"01K7…","name":"chorus-hum","path":"Motifs/chorus-hum.mid","kind":"midi",
 "parents":["01K7…"],"provenance":{"source":"chorus-hum.wav","model":"torchcrepe","at":"2026-10-15T20:14:00Z"},"confidence":0.82}}
```

```
sf hear record 8bars take.wav     # microphone to a file, with a count-in click; needs microphone consent
sf hear transcribe take.wav       # hum or playing to notes, with feel kept as unquantised offsets
sf hear stems ref.wav             # a reference track into four motifs: drums, bass, vocals, other (reply carries `motifs`, a list)
```

`hear stems` replies with `motifs`, a list of four, one sidecar each, all with the reference track as parent:

```
{"status":"done","motifs":[
 {"id":"01K7…","name":"aint-no-sunshine-drums","path":"Motifs/aint-no-sunshine-drums.wav","kind":"audio","parents":["01K7…"],
  "provenance":{"source":"aint-no-sunshine.mp3","model":"demucs-htdemucs 4.1.0","at":"2026-10-15T20:13:28-07:00"},"confidence":0.91},
 {… "-bass" …}, {… "-vocals" …}, {… "-other" …}]}
```

A motif's lineage travels with everything you write from it; see [motif.md](motif.md). Confidence below 0.5: show the musician the result before you build on it.

Confidence means different things per verb. For `transcribe` it is measured on the take (pitch periodicity and note stability). For `stems` the model gives no per-stem score: the number is a prior from the model's published separation quality for that stem, and the reply's `evidence` block (energy share, silence, residual, bleed) says only whether a stem is empty or the split is incoherent, never whether it sounds clean. A near-silent stem means the track has no such part, not a failed split; say so instead of quoting the number (`prototype/hear-stems/README.md`).
