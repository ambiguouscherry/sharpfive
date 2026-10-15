# motif: the musician's material and its lineage

A motif is one file plus a sidecar in `Motifs/` beside the project (or `~/.sharpfive/inbox/` with no project open). Full model: [spec/motif-lifecycle.md](../../motif-lifecycle.md).

```
sf motif list                      # every motif here: name, kind, source, parents, placed
sf motif show chorus-hum           # the sidecar and the lineage back to the roots
sf motif text chorus-hum "bridge"  # the musician's words
sf motif rename chorus-hum bridge-hum
sf motif adopt                     # inbox into this project
sf motif forget bridge-hum         # to Motifs/.trash/; always a gate
```

Rules you follow:

- Say the name, never the id.
- Every WRITE takes `--from <name>`. No motif to name: ask, do not invent one.
- `hear`, FETCH, the first run in a project, a brief you act on, every WRITE and every EDIT make motifs for you. You never create one by hand.
- `placed` says where it went, export says what is there. Do not confuse them.
