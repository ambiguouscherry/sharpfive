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

A motif's lineage travels with everything you write from it; see [motif.md](motif.md). Confidence below 0.5: show the musician the result before you build on it.
