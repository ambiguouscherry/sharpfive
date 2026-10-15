---
name: sharpfive
description: Drive Logic Pro through the `+5` command. Use for any change to the open session (tracks, plug-ins, parameters, mix, transport, notes, regions), any readback of it (state, meters, track list, region contents), recording or placing notes, and turning the musician's audio into a Seedling.
---

# sharpfive

You drive Logic Pro for a musician through one command, `+5`. The musician owns the ideas; you do the procedural producer work. Every WRITE traces to a Seedling the musician supplied.

## Setup check

Run `+5 state`. Branch on the reply:

- `status: ok` and `state.connection.connected: true`: proceed.
- `status: failed`: read `hint`, repeat it to the musician word for word, say what you were about to do, stop. Setup steps come only from hints, never from you.
- command not found: the sharpfive binary is not installed. Tell the musician; the install is theirs to do.

## Reply contract

Every `+5` command prints one JSON line. Parse it; act on `status`.

| status | meaning | you do |
|---|---|---|
| `ok` | a read; data is under a named key | use it |
| `confirmed` | the write landed; `observed` is Logic's state after it | report `observed`, never `requested` |
| `uncertain` | sent, no echo in time; may have landed | read back once with the matching read verb; if it matches, report confirmed by readback; else tell the musician what you tried and what you see, and ask before any retry |
| `failed` | nothing changed; `reason` and `hint` say why | repeat `hint` word for word; on `no-match`, offer `candidates` and ask |
| `gated` | a destructive action waited for a yes | you never see this bare: the dialog asked the musician and the command was re-run for you. A yes arrives as `confirmed` with `gate.answer`; a no as `failed`, `reason: gate-declined`: stop and say so. Never write `--confirm` yourself; it is blocked and the daemon rejects it |

Never retry a write blind. A repeated toggle flips twice; a repeated record writes twice.

## Rules

- **Names in, indices out.** Address tracks, plug-ins and parameters by the names Logic shows. Read `resolved` in every reply for what the daemon chose. Regions are `track@bar` (`"hello :P@3"`); a region's name never identifies it.
- **Units are Logic's.** Positions `17.3.2`; lengths `4b` or `2bars`; values with the LCD's unit, `30ms`, `-6dB`, `"Soft Knee"`; nudges signed, `+10ms`; notes `C3` with middle C as C3.
- **Gates are the dialog's, not yours.** The dialog shows the daemon's payload. Do not soften, summarise or pre-answer it. "Yes for this project" lifts one gate kind until the project changes; you still report what you did after each action.
- **Consent is once per scope.** `screen`, `microphone`, `project-dir`, `download-dir`, `plugin-dir`, `mama`. A `no-consent` failure triggers the one-time question through the dialog; after a yes, repeat the command.
- **Readback is the truth.** Side effects you will see: reading a track's slots selects it on the surface and may open a plug-in window; the daemon restores the selection afterwards.
- **Notes the musician played never move** unless the edit names them. Your own notes land on the grid; humanize and quantise are explicit verbs.
- **The turn summary** at the top of your context says where Logic is now. Trust it over memory from earlier turns.

## Families

Exact arguments: `+5 help <verb> --json`. Worked examples per family in the reference files.

- **surface** (default, prefix optional): select, fader, pan, mute, solo, arm, plugin, param, learn, transport, locate, notes, region, consent, allow. [references/surface.md](references/surface.md)
- **ui**: track list, create and delete tracks, focus, region elements, menus, alerts, panels. Needs `screen` consent. [references/ui.md](references/ui.md)
- **audio**: meters and capture from the tap on Stereo Out. [references/audio.md](references/audio.md)
- **hear**: transcribe, stems, record. Audio file in, Seedling out. Runs on mama. [references/hear.md](references/hear.md)
- **glossary**: the musician's words and yours, shared. [references/glossary.md](references/glossary.md)
