# Context

Glossary of terms for the sharpfive domain. Vocabulary only — no implementation detail.

## Terms

### Verb

One of the three capabilities the agent has against a Logic session: **LISTEN** (perceive the session — audio analysis, MIDI capture, state readback), **WRITE** (put new musical material into the session), **EDIT** (change what's already there — parameters, mix, regions). EDIT and LISTEN are core; WRITE is supporting.

### Limb

One bridge between the agent brain and Logic, exposed to pi as a CLI tool + skill. Each limb covers part of a verb; no limb covers everything.

### Procedural producer work

The friction-heavy, non-creative work around making music: setting up plugin environments, creating and naming tracks, gain staging, routing. The agent's primary job. Contrast with **musicianship** — writing and refining the music itself, which stays with the human. The agent may sketch ideas (arrangements, scratch parts) but does not own the music.

### Readback

Verifying an action landed rather than firing blind — via control-surface feedback, accessibility-tree inspection, or screenshots. Every EDIT limb needs a readback channel.

### Round-trip

The pattern for editing notes in an existing region despite no protocol existing for it: export the region as MIDI, edit the sequence outside Logic, replace the region. Converts an impossible operation into two solved ones.
