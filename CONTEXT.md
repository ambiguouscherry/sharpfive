# Context

Glossary of terms for the sharpfive domain. Vocabulary only — no implementation detail.

## Terms

### Verb

One of the five capabilities the agent has: **LISTEN** (perceive the session and the musician — audio analysis, stem separation, transcription, state readback, vocalizations), **WRITE** (put new musical material into the session — parts, arrangement, composition — always tracing to a Seedling), **EDIT** (change what's already there — parameters, mix, regions, project setup), **BUILD** (author, build, and install new tooling for the musician, chiefly custom AU plugins), **FETCH** (find outside material and bring it in as Seedlings — internet sources and local sample libraries).

### Seedling

Musician-supplied starting material that a workflow carries toward a finished track. Takes any form: a hummed or played phrase, a vocalization, a text brief, a reference track or sample, a rough MIDI sketch, a half-done project. Every Seedling carries its provenance (where it came from). Every WRITE must trace back to a Seedling — this traceability is how the agent stays the musician's collaborator rather than the author.

### Vocalization

Non-textual musical input from the musician — singing, humming, beatboxing, mouth-drumming. A form of Seedling the agent must interpret (melody, rhythm, feel) rather than transcribe as words.

### Gated action

An action the agent must not take without the musician's explicit confirmation: a FETCH download, a BUILD install into the plugin folder, a destructive EDIT (deleting regions, replacing plugins in a live session).

### Limb

One bridge between the agent brain and Logic, exposed to pi as a CLI tool + skill. Each limb covers part of a verb; no limb covers everything.

### Procedural producer work

The friction-heavy, non-creative work around making music: setting up plugin environments, creating and naming tracks, gain staging, routing, finding and preparing samples, building a missing tool. The agent's primary job. Contrast with **musicianship** — the ideas and taste that drive a track, which stay with the human. The agent may compose and arrange, but only in service of a Seedling the musician supplied; it never originates the idea.

### Readback

Verifying an action landed rather than firing blind — via control-surface feedback, accessibility-tree inspection, or screenshots. Every EDIT limb needs a readback channel.

### Round-trip

The pattern for editing notes in an existing region despite no protocol existing for it: take an export snapshot, edit the note list outside Logic, clear the old region, place the edited one, compare. Converts an impossible operation into solved ones.

### Strip

One of the eight track positions a control surface shows at one time. A strip has a fader, a knob, and a short name cell. Strip 1 is the left-most position, not a fixed track.

### Bank

The eight tracks the strips show right now. Moving the bank swaps which tracks the strips address.

### Assignment mode

What the surface's knobs control right now: track, pan, send, plug-in list, plug-in edit, instrument list. The surface announces it; the agent reads it rather than assuming it.

### Slot

One plug-in position on a track: the instrument slot or insert 1, 2, 3 and so on. Instruments and effects are inserted by the same mechanic into different slots.

### Parameter page

One screen of up to eight parameters in plug-in edit view. A plug-in spans one or more pages; the agent pages to reach a parameter.

### Transient

A short-lived overlay the surface shows for about two seconds after a touch or a page change, carrying extra facts (full parameter name, unit, page count) that the steady display abbreviates. A source of facts, not noise.

### Region

One block of MIDI events on one track, with a start and an end. The unit a round-trip edits.

### Region handle

How the agent points at one region: the track plus the start bar, as read from Logic's accessibility tree. A region's name is shown beside the handle but never identifies it, because names repeat.

### Export snapshot

The MIDI file the agent writes out of Logic. A copy of every region at one moment. Taking one changes nothing in the project. The snapshot taken before an edit is also the proof for undo.

### Place

Put a prepared MIDI file onto a track at a bar. Positions in the file land exactly. The way an edited region goes back into Logic.
_Avoid_: import, paste, drop

### Record

Play notes into Logic in real time from the agent's own MIDI source. Notes land late by a varying amount. The way new material is written when the musician asks for a performance; never the way an edit goes back.

### Merge

Recording with REPLACE off. The new notes join the old notes in the same region.

### Replace

Recording with REPLACE on. The old notes under the recording are erased, from the record start to the STOP press.

### Compare

The readback for a region edit: export again, parse, and check the result against the plan. The edit is confirmed only when they match.

### Take folder

A stack of recordings of the same bars on one track. Logic plays one take and keeps the rest. The round-trip refuses to edit inside one.

### Humanize

Move notes and velocities off the grid by small amounts, on request. The opposite of quantise. The agent's own new notes land on the grid unless asked otherwise; notes the musician played are never moved unless the edit names them.
