# hear: audio in, Seedling out

Named, not yet specced: the models are proven in research, the verbs are not. Runs on mama over ssh (`mama` consent). Shape of every reply:

```
{"status":"done","seedling":{"path":"~/sharpfive/seedlings/2026-10-15-hum-1.mid","kind":"midi",
 "provenance":{"source":"take.wav","model":"torchcrepe","at":"2026-10-15T20:14:00Z"},"confidence":0.82}}
```

```
+5 hear record 8bars take.wav     # microphone to a file, with a count-in click; needs microphone consent
+5 hear transcribe take.wav       # hum or playing to notes, with feel kept as unquantised offsets
+5 hear stems ref.wav             # a reference track into stems
```

A Seedling's provenance travels with everything you write from it. Confidence below 0.5: show the musician the result before you build on it.
