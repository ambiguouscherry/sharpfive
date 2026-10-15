---
status: accepted
date: 2026-10-15
---

# Motifs live in a folder beside the Logic project and link to each other by id

Every motif is one file plus a sidecar, kept in `Motifs/` in the Logic project's parent directory, shared by every project file saved in that directory. The obvious alternatives were one global store under `~/.sharpfive/` (easy to search, but a project copied to another Mac or handed to a collaborator would arrive without its motifs) and a folder inside the project bundle (undocumented format, out of scope). A folder beside the project travels with the song, needs only the `project-dir` consent that already exists, and matches how Logic users think: one directory per song, Save As versions beside it. Motifs made with no project open wait in `~/.sharpfive/inbox/` until adopted. Parents link by a ULID held in the sidecar, not by file name, because the agent names motifs from context and the musician may rename them, in Finder included; a name-keyed chain would break on every rename. Decided in [#19](https://github.com/ambiguouscherry/sharpfive/issues/19).

## Consequences

- Moving or renaming a motif file breaks nothing as long as its sidecar moves with it. The agent renames both together; a Finder rename of only one leaves an orphan the agent reports.
- Nothing is indexed. `sf motif list` scans the sidecars every time. If a project ever holds thousands of motifs this needs revisiting.
- FETCH downloads land here directly, so the `download-dir` consent names the same folder. There is no separate downloads folder to keep in sync.
