# Spec: motif lifecycle

Resolves [#19](https://github.com/ambiguouscherry/sharpfive/issues/19). Three grilling rounds with Margot on 2026-10-15. Vocabulary in [CONTEXT.md](../CONTEXT.md); the storage choice in [ADR 0005](../docs/adr/0005-motifs-live-beside-the-project-linked-by-id.md). Renames "Seedling" to "motif" everywhere.

## 1. The model in one paragraph

One file is one motif. Every motif has a sidecar, `<file>.motif.json`, that carries its id, name, kind, provenance, parents, confidence, the musician's text and a placed log. Motifs form a chain: a transcription names the take it came from, a stem names its reference track, a WRITE names the motifs it was asked to build on. A root has no parent. Every WRITE takes `--from` and fails without it. Motifs live in `Motifs/` beside the project, or in the inbox when no project is open.

## 2. Where

| Place | When | Consent |
|---|---|---|
| `<project parent dir>/Motifs/` | a Logic project is open | `project-dir` |
| `~/.sharpfive/inbox/` | no project is open | none (the agent's own dir) |
| `Motifs/.trash/` | forgotten motifs | `project-dir` |
| `Motifs/.snapshots/` | the round-trip's before and after exports; not motifs; pruned by the agent | `project-dir` |

The folder belongs to the directory, not to a project file. Any `.logicx` saved in that directory shares it. A `Motifs/` folder that arrives from another Mac works as it is, because the links inside are ids.

FETCH downloads land straight in `Motifs/` or the inbox. The FETCH gate's destination line shows that path. `download-dir` consent means "the agent may write fetched files into motif folders".

## 3. The sidecar

```json
{
  "id": "01K7M3Q4V8ZJ2X9R5TB6N0HW3E",
  "name": "chorus-hum",
  "kind": "midi",
  "source": {"by": "hear", "model": "torchcrepe", "version": "0.0.24"},
  "parents": ["01K7M3PZ0M7C4D1A8F2G6H5J9K"],
  "at": "2026-10-15T21:30:20Z",
  "tempo": 92, "key": null, "bars": 4,
  "confidence": 0.91,
  "text": "the one for the bridge",
  "placed": [{"region": "Inst 2@17", "at": "2026-10-15T21:41:02Z"}]
}
```

| Field | Rule |
|---|---|
| `id` | ULID, made once, never changed. The link every child uses. |
| `name` | the file's base name. Two to four words from the turn that made it, kebab case, `-2` on a collision. The agent speaks the name, never the id. |
| `kind` | `audio`, `midi`, `text`, `project` |
| `source.by` | `mic`, `file`, `fetch`, `hear`, `edit`, `write`, `project` — plus the detail for that source: device for mic; URL and licence as the source states it for fetch; model and version for hear; the brief's wording for write |
| `parents` | ids. Empty for a root. One or more. |
| `at` | when the motif was made |
| `tempo`, `key`, `bars` | only when known; `null` is allowed |
| `confidence` | 0 to 1, derived motifs only |
| `text` | the musician's words. The only field the musician edits. |
| `placed` | append-only log of `track@bar` and time, written by the verb that placed it. Never trimmed when a region is deleted; export is the truth for what is there now. |

No index file. The folder is the index: the agent scans sidecars when it needs the list.

## 4. How motifs are made

Creation has no verb. Every limb that makes a file makes a motif:

| Limb | Motif | Root? |
|---|---|---|
| `sf hear record` | the take, `kind: audio`, `source: mic` | yes |
| `sf hear transcribe` | the MIDI file, parent = the take | no |
| `sf hear stems` | **four motifs** (drums, bass, vocals, other), named `<parent>-drums` and so on, one parent each. The reply returns a list. | no |
| FETCH download | the file, `source: fetch` with URL and licence | yes |
| a brief the agent acts on | `<name>.md`, `kind: text`, the full brief in `text` | yes |
| first `sf` run in a project with regions | the whole-project MIDI export, `kind: project`, named after the project; audio regions listed by name in `text`, not copied | yes |
| every WRITE | the placed file, `source: write`, parents = its `--from` | no |
| every round-trip EDIT | the edited file, `source: edit`, parent = the motif exported from (or the project root) | no |

Chat that leads to no WRITE is not saved. The round-trip's verification snapshots are not motifs.

## 5. Into Logic

MIDI and audio go in the same way: a new track named after the motif, locate to the bar, `File > Import > MIDI File…` or `File > Import > Audio File…` (ADR 0003 for MIDI; the audio panel is proven by a prototype ticket the way #32 proves MIDI). The region gets the motif name, so the trace is visible in the Arrange window. A text motif never enters Logic; WRITEs trace to it.

## 6. The WRITE rule

Every WRITE verb takes `--from <name>`, one or more. Without it the reply is `failed` with the hint "name the motif this comes from". If the agent has none to name, it asks the musician before writing. The written file becomes a motif whose parents are the `--from` motifs. Traceability is therefore a type check on the call, and a lineage any `sf motif show` can print.

## 7. Verbs

All under `sf motif`. Reads print one JSON line like every `sf` reply.

| Verb | Does | Gate |
|---|---|---|
| `list` | every motif in the project folder and the inbox: name, kind, source, parents, placed | none |
| `show <name>` | the full sidecar plus the lineage back to the roots | none |
| `text <name> "words"` | set the musician's text | none |
| `rename <name> <new>` | rename file and sidecar together; children unaffected | none |
| `adopt` | move the inbox into the open project's `Motifs/`; offered when a project opens | none |
| `forget <name>` | move file and sidecar to `Motifs/.trash/`; children keep the id and the sidecar of each child records the forgotten parent's name | always ask (new gate kind `motif-forget`) |

Nothing more. Anything else is a workflow and belongs to stage 4.

## 8. Failure cases

| Case | Reply |
|---|---|
| a motif file with no sidecar, or a sidecar with no file | `list` reports it as an orphan with a hint to rename the pair together |
| a parent id that no sidecar carries (deleted in Finder) | `show` prints the chain to that point and marks the link broken; the motif is still usable |
| `--from` names a motif not in this project or the inbox | `failed`, hint names the folders searched |
| two projects in one directory | they share the folder by design; `list` does not filter by project |

## 9. Out of this spec

The audio-import prototype, the motif verbs' implementation, how arrangement flows combine motifs (stage 4), and the interface's view of lineage (#21).
