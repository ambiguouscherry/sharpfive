# Context

Glossary of terms for the sharpfive domain. Vocabulary only — no implementation detail.

## Terms

### Verb

One of the five capabilities the agent has: **LISTEN** (perceive the session and the musician — audio analysis, stem separation, transcription, state readback, vocalizations), **WRITE** (put new musical material into the session — parts, arrangement, composition — always tracing to a motif), **EDIT** (change what's already there — parameters, mix, regions, project setup), **BUILD** (author, build, and install new tooling for the musician, chiefly custom AU plugins), **FETCH** (find outside material and bring it in as motifs — internet sources and local sample libraries).

### Motif

Musician-supplied starting material that a workflow carries toward a finished track, and everything the agent makes from it. Takes any form: a hummed or played phrase, a vocalization, a text brief, a reference track or sample, a stem, a rough MIDI sketch, a half-done project. One file is one motif. Every motif carries its provenance and names its parents. Every WRITE must trace back to a motif — this traceability is how the agent stays the musician's collaborator rather than the author.
_Avoid_: seedling, seed, idea, source material

### Provenance

Where a motif came from: a microphone take at a time, a URL and its licence, a model run over another motif, an edit or a WRITE. Fixed when the motif is made; never edited.

### Parent

A motif that another motif was made from. A transcription's parent is the take; a stem's parent is the reference track; a WRITE's parents are the motifs it was asked to build on. A motif may have several parents.

### Root motif

A motif with no parent: a take, a fetched file, a brief, or the project's own material on the day the agent first saw it.

### Lineage

The chain of parents from one motif back to its roots. What "traces to a motif" means: the lineage reads all the way to something the musician supplied.

### Motif name

The two to four words the agent gives a motif from the conversation that made it ("chorus hum", "shell shock bass"). What the musician and the agent say. The musician can rename; the lineage does not depend on the name.

### Sidecar

The small file beside a motif's file that carries its provenance, parents, name, text and placed log. The motif's file holds the music; the sidecar holds the facts.

### Text

The musician's own words about a motif, kept in its sidecar. Free text. Not a musical note.
_Avoid_: note, comment, description

### Inbox

Where motifs go when no Logic project is open. Emptied into a project by adopting.

### Adopt

Move the inbox's motifs into the open project's motif folder. Offered when a project opens.

### Placed log

The list in a sidecar of where a motif has gone into Logic: track and bar, with the time. A record of what the agent did, not a claim about what is in the project now; export is the truth for that.

### Forget

Put a motif out of the way without destroying it: the file and its sidecar move to the motif folder's trash. Always asks. Children keep their parent link.
_Avoid_: delete, remove

### Vocalization

Non-textual musical input from the musician — singing, humming, beatboxing, mouth-drumming. A form of motif the agent must interpret (melody, rhythm, feel) rather than transcribe as words.

### Gated action

An action the agent must not take without the musician's explicit confirmation: a FETCH download, a BUILD install into the plugin folder, a destructive EDIT (deleting regions, replacing plugins in a live session). Contrast with **consent**, which is about reaching a resource, not about one action.

### Gate

The stop before one gated action. The agent's call comes back as gated with what would change; the action runs only when the call is repeated with confirmation. The musician sees the gate as a dialog with five lines: the action, the target, the change, whether undo exists, and whether an allowance is offered.

### Gate token

The one-time secret the daemon attaches to a gated reply. The extension keeps it out of the agent's sight and spends it on the re-run after the musician's yes. Without it, `--confirm` does nothing. It is what makes the dialog the only way through a gate.

### Gate kind

A class of gated action: region replace, record over, plug-in replace, plug-in remove, delete track, plug-in install, file download. Allowances are granted per kind. Kinds with a snapshot or an undo behind them can be lifted for a project; kinds whose yes loses something code cannot rebuild always ask.

### Allowance

A "yes" that covers every later gate of one kind until it expires: "yes for this project". It ends when the project changes. The agent still reports what it did after each action.

### Consent

Permission to reach a resource: the screen, the microphone, a directory, the ML box. Asked once, remembered on the machine, never asked again for that scope. Says nothing about what the agent may do once inside; gates do that. The musician can list and revoke consents.

### Limb

One bridge between the agent brain and Logic, exposed to pi as a CLI tool + skill. Each limb covers part of a verb; no limb covers everything.

### Tool

One thing the agent can call. In sharpfive every limb is reached through one command, `sf`, run by the agent's shell tool; its families (surface, ui, audio, hear) are the tools the agent thinks in.

### Skill

A document the agent reads to learn how to use tools. The agent sees only the skill's name and one-line description until it needs it, then reads the whole document. This is progressive disclosure.

### Reply

The one line every `sf` command prints. It always carries a status. Writes add what was requested and what was observed. Failures add a reason and a hint.

### Hint

One sentence in a failed reply, written for the musician, that says what to do next. The agent repeats it as it is and never invents setup steps.

### Turn summary

The few lines about Logic's state the agent is given at the start of every turn: connected or not, the selected track, the transport, the assignment mode, active allowances.

### Position

A place in the song, written as bar, beat and division: `17`, `17.3`, `17.3.2`. Bars count from 1 as Logic shows them.

### Hear

The verb family for LISTEN deep: turn an audio file into a motif (transcription, stems, a microphone take). LISTEN is the umbrella over hear, the audio tap and screen reads.

### Procedural producer work

The friction-heavy, non-creative work around making music: setting up plugin environments, creating and naming tracks, gain staging, routing, finding and preparing samples, building a missing tool. The agent's primary job. Contrast with **musicianship** — the ideas and taste that drive a track, which stay with the human. The agent may compose and arrange, but only in service of a motif the musician supplied; it never originates the idea.

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
