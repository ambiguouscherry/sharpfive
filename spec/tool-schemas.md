# Tool schemas and skill docs: what pi sees of each limb

Resolves [Grilling: spec pi tool schemas and skill docs for the surviving limbs](https://github.com/ambiguouscherry/sharpfive/issues/11), 2026-10-15. The last decision layer before the build plan. Builds on the EDIT limb contract (`spec/edit-limb.md`), the round-trip design (`spec/round-trip-edit.md`), the audio tap (#7), UI scripting (#9) and the BUILD loop (#15, #16). pi facts per `research/pi-extension-idiom.md`. Vocabulary per [CONTEXT.md](../CONTEXT.md). See [ADR 0004](../docs/adr/0004-shell-plus-skill-now-pi-fork-for-market.md).

## 1. Shape

- **The command is `sf`.** One Swift binary (ADR 0002) with the daemon and every verb. *Renamed 2026-10-15 from `+5` after #40:* under `sh -c "+5 …"` every POSIX shell reads a leading `+` as an option toggle (`sf: invalid option`), and pi's bash tool spawns exactly that; `sf` has no such hazard and is free on PATH. Everything that is not typed in a shell is named `sharpfive`: the pi package, the skill, the socket, the config folder `~/.sharpfive/`.
- **pi reaches every limb through its shell tool.** No custom pi tool per verb. The skill is the schema: it tells pi the families, the reply contract and the rules; `sf help <verb> --json` is the source of truth for each verb's arguments, generated from the binary so the docs cannot drift.
- **One thin pi extension** does two things only: shows gates in pi's own confirm dialog (a `tool_call` hook on shell commands that start with `sf`), and writes the turn summary into the system prompt before each turn (`before_agent_start`), with mid-turn pushes from the daemon's `watch` stream (`pi.sendMessage`). It defines no verbs and touches no MIDI.
- **Product form.** The extension is the development form. For market the product is a modified copy of pi's source with the same code built in, not an extension installed into stock pi.
- **Five verb families, one mechanism each:** `surface` (the control-surface daemon verbs, the default family so the prefix is optional), `ui` (accessibility reads and menu presses), `audio` (the tap), `hear` (LISTEN deep: audio file in, motif out; named, not yet specced), `motif` (the musician's material and its lineage: [spec/motif-lifecycle.md](motif-lifecycle.md), added 2026-10-15 by #19).
- **Typed pi tools and an MCP wrapper** stay possible later as layers over the same CLI (map Notes).

## 2. Reply

Every command prints exactly one JSON line. `--pretty` prints a readable layout for a human.

| Field | Reads | Writes | Failures |
|---|---|---|---|
| `status` | `ok` | `confirmed` \| `uncertain` \| `failed` \| `gated` | `failed` |
| data | under a named key (`state`, `tracks`, `inventory`, `meters`, …) | | |
| `requested`, `observed` | | always; `observed` is the daemon's view after the action | |
| `resolved` | | `{track, strip, slot, page, cell}` as resolved from names | |
| `settledAfterMs` | | | |
| `reason` | | | short machine code (§6) |
| `hint` | | | one sentence written for the musician |
| `candidates` | | | on `no-match`: the closest names |
| gate payload | | on `gated` (§4) | |

**`uncertain` rule.** pi reads back once (`state` or the matching read verb). If the observed value matches the request, pi reports it as confirmed by readback. If not, pi tells the musician what it tried and what it sees, and asks before any retry. pi never retries a write blind: a repeated toggle flips twice, a repeated record writes twice.

## 3. Families and verbs

Arguments in full come from `sf help <verb> --json`. This table fixes the verbs, what each returns, and the gate kind.

### surface (daemon, control surface; prefix optional)

| Verb | Returns | Gate kind |
|---|---|---|
| `state`, `raw`, `watch` | the parsed model (§3 of the EDIT contract); `watch` streams events | |
| `tracks`, `scan` | directory; `scan` reads every slot | |
| `select <track>`, `bank <±n>` | resolved strip | |
| `fader set|get`, `pan`, `mute`, `solo`, `arm` | observed value | |
| `plugin list` | plug-ins Logic offers | |
| `plugin inventory <track>` | slots by MCU index (the inspector hides empty slots; the MCU index is the key) | |
| `plugin insert <track> <slot> <name>` | resolved slot | `plugin-replace` when the slot is occupied |
| `plugin remove <track> <slot>` | | `plugin-remove` (unverified, #28) |
| `plugin bypass <track> <slot>` | | none (reversible; unverified, #28) |
| `param list|get|set|nudge` | observed value with unit | |
| `learn <track> <slot>` | full names collected | |
| `transport play|stop`, `locate <position>`, `cycle`, `replace`, `drop` | transport state | |
| `transport record [--replace]` | region written | `record-over` when REPLACE is on |
| `notes send <file|inline>` | notes queued, host-time stamped | none (record is the gate) |
| `region replace <track@bar> <file>` | the round-trip in one verb: snapshot, element read, clear, place, compare | `region-replace` |
| `region export [<track@bar>]`, `region read <track@bar>`, `region compare <snapshot>` | snapshot path; element facts; diff | |
| `region rename <track@bar> <name>` | element description | none (never overwrites a musician's name) |
| `region undo <snapshot>` | compare result | |
| `consent list|revoke <scope>` | consent file contents | |
| `allow <kind> [--revoke]` | active allowances | |
| `help [<verb>] [--json]` | the schema | |

Stereo Out and Master are strips in the selection view; `<track>` accepts them.

### ui (accessibility; needs `screen` consent)

| Verb | Returns |
|---|---|
| `ui tracks` | the Tracks header list: index, name, focus, mute, solo, arm |
| `ui track create <type> [--name]` | the new track as read back; focus lands on it |
| `ui track delete <name>` | gate kind `track-delete`; refuses unless the readback shows that track focused |
| `ui focus <name>` | arrow-walk-and-verify, or MCU SELECT; never an AX write |
| `ui regions <track>` | region elements: start, end, name, loop, contents note, selected, muted |
| `ui menu <path>` | presses a menu item by title; returns the focused window afterwards |
| `ui alert <button>` | presses a button on a sheet or alert window by title |
| `ui panel save|open <path>` | drives the panel-service process; `uncertain` if the press did not take |
| `ui dump [<window>]` | the AX tree, for debugging |

### audio (tap; no consent, the tap is inside Logic)

| Verb | Returns |
|---|---|
| `audio meters [--for <length> | --until stop]` | 100 ms windows of peak, RMS, clipping, each stamped with its position; summary: max peak, clip count, loudest bar |
| `audio capture <file> [--for <length>]` | the mix written to a file, 16-bit PCM as the tap delivers it |
| `audio status` | sender present, format, underflows |

### hear (LISTEN deep; named, not specced; runs on mama)

| Verb | Returns |
|---|---|
| `hear transcribe <audio>` | a motif: MIDI path, provenance (source file, model, time), confidence 0–1 |
| `hear stems <audio>` | four motifs (drums, bass, vocals, other), one parent each; the reply carries `motifs`, a list |
| `hear record [<length>] <file>` | microphone capture to a file (needs `microphone` consent) |

Schemas land after the prototype tickets prove the models ([#38](https://github.com/ambiguouscherry/sharpfive/issues/38), [#39](https://github.com/ambiguouscherry/sharpfive/issues/39)). The extension is built in [#40](https://github.com/ambiguouscherry/sharpfive/issues/40). Reply shape fixed now: `status: done | failed`, `motif: {id, name, path, kind, parents, provenance, confidence}` (`motifs`, a list, for stems). The sidecar beside the file carries the same facts: [spec/motif-lifecycle.md](motif-lifecycle.md).

## 4. Gates

A gated verb without `--confirm` returns `status: gated` and does nothing. The extension's `tool_call` hook sees any `sf` command that returned `gated` and opens pi's confirm dialog from the payload, never from pi's words. The dialog has five fixed lines and three buttons: **No**, **Yes**, **Yes for this project**.

| Line | Content | Example |
|---|---|---|
| action | one sentence | Replace the region on hello :P at bar 3. |
| target | resolved names | hello :P, bar 3 to 4.3, named "second" |
| change | word diff or short list, first few named | 2 notes moved, 1 added: C3 3.2 → 3.3, + E3 4.1. Everything else stays. |
| undo | available and how, or not | Snapshot kept; Edit > Undo verified by export. |
| allowance | offered or not | Yes for this project lifts region edits until the project changes. |

Payload fields: `kind`, `action`, `target`, `diff`, `undo`, `allowance: offered | none`, `token`.

**Gate token** (added 2026-10-15, #40). The daemon issues a one-time `token` with every `gated` reply. The extension strips it from what the model sees and, on yes, re-runs the command with `--confirm <token>` (plus `--allow-project` for "Yes for this project"). A `--confirm` without a valid token fails `confirm-token-invalid`; tokens are single use and expire after ten minutes. The extension also blocks any agent-written `--confirm`, but the token is the guard: no shell wrapping gets past it. Without a dialog (print mode) a gated reply becomes `failed`, `reason: gate-no-dialog`.

**Gate kinds.** Lifted kinds accept "Yes for this project"; the allowance lives in the daemon and dies when the project changes or the daemon restarts. `allow <kind>` grants or revokes it from the command line, and refuses to grant when stdin is not a terminal (`tty-required`), so the agent's shell cannot grant itself an allowance; revoking is always allowed. Always-ask kinds show two buttons.

| Kind | Undo | Default |
|---|---|---|
| `region-replace` | snapshot + Edit > Undo | lift per project |
| `record-over` | Edit > Undo | lift per project |
| `fetch-download` | delete the file | lift per source per project |
| `plugin-replace` | old settings lost | always ask |
| `plugin-remove` | not reversible | always ask |
| `track-delete` | Undo, but regions go with it | always ask |
| `build-install` | manual | always ask |
| `motif-forget` | moves to `Motifs/.trash/`, restorable by hand | always ask |

**FETCH gate** (tool not built; the gate is fixed): source URL or library path, licence as the source states it, size, destination path, the provenance line that will be attached to the motif. Fires before any byte lands. Search and propose are free.

**BUILD gate** (tool not built; the gate is fixed): plug-in name and version, the brief it was built from, install path, whether it overwrites an installed version, that Logic must restart to see a new component (#36). Fires before the copy into the plug-in folder. Building in a scratch folder is free.

## 5. Consent

Consent is permission to reach a resource. Asked once, remembered, never asked again for that scope. It says nothing about what the agent may do inside; gates do that.

| Scope | Needed by |
|---|---|
| `screen` | the `ui` family (accessibility) |
| `microphone` | `hear record` |
| `project-dir` | reading and writing files beside the Logic project (snapshots, SMFs, the `Motifs/` folder) |
| `download-dir` | FETCH; resolves to the project's `Motifs/` folder or the inbox, never a separate downloads folder |
| `plugin-dir` | BUILD install |
| `mama` | the ssh link for `hear` |

Stored in `~/.sharpfive/consent.json` on this machine, written by the extension when the musician says yes, read by the CLI. Survives pi restarts and new sessions. `sf consent list` shows it; `sf consent revoke <scope>` takes one back. A verb that needs a scope without consent returns `failed`, `reason: no-consent`, with the hint naming the scope; the extension turns that into the one-time question.

## 6. Failures

One shape for every failure: `status: failed`, `reason`, `hint`. The skill tells pi: repeat the hint word for word, say what you were trying to do, stop. pi never invents setup steps.

| Reason | Hint (written once, here) |
|---|---|
| `daemon-not-running` | only after the CLI tried to start it: "sharpfive could not start its daemon. Run `sf daemon` in a terminal and send me the output." |
| `not-connected` | "Logic is not talking to sharpfive. Logic › Control Surfaces › Setup › Install › Mackie Control, both ports = sharpfive." |
| `no-consent` | "sharpfive needs access to <scope>. Say yes here and I will remember it." |
| `ax-not-trusted` | "macOS has not granted sharpfive accessibility access. System Settings › Privacy & Security › Accessibility › sharpfive." |
| `panel-press-failed` | "Logic's save or open panel did not take the press. The project is unchanged. Tell me to try again." |
| `no-match` | "I could not find <name>. Closest: <candidates>." |
| `region-refused` | "That region is looped or a take folder, and I only edit plain regions." |
| `mama-unreachable` | "The ML box (mama) is not answering over ssh." |
| `timeout` | "Logic did not answer in time. Nothing was changed as far as I can see." |
| `confirm-token-invalid` | "The gate was not answered in the dialog, so nothing was changed. Run the command again without --confirm and let the musician answer." |
| `gate-declined` | (written by the extension) "The musician said no. Stop and say so; do not retry." |
| `tty-required` | "Allowances are granted by the musician in a terminal, not by the agent. Answer 'Yes for this project' in the gate dialog instead." |

## 7. Turn summary and pushes

Before each turn the extension runs `sf state` and appends about five lines to pi's system prompt: connected or not (with the hint if not), the selected track, transport state and position, assignment mode, active allowances. Mid-turn the daemon's `watch` stream pushes a message into pi's loop only for: connection lost, transport started or stopped by the musician, track changed by the musician. Everything else is a `sf state` call. *Measured 2026-10-15 (#40):* the summary costs 54 input tokens per turn; connection lost is delivered as a steer (it interrupts), the musician's moves as next-turn context (they never trigger a reply).

## 8. Units

| Kind | Form | Example |
|---|---|---|
| position | `bar[.beat[.division]]`, bars from 1 as Logic shows them | `17`, `17.3`, `17.3.2` |
| length | beats or bars with a suffix; never ms | `4b`, `2bars` |
| parameter value | number plus the LCD's unit; words for discrete values; signed for nudges | `30ms`, `-6dB`, `50%`, `"Soft Knee"`, `+10ms` |
| track | the name as shown; case-insensitive on the first six characters | `"hello :P"` |
| region | `track@bar` | `"hello :P@3"` |
| slot | `inst` or the MCU index | `inst`, `1`, `2` |
| note | name plus octave, middle C is C3 | `C3` |

## 9. The skill

Lives in the sharpfive pi package at `skills/sharpfive/`. Model-invoked (pi reaches it from its one-line description). Draft in `spec/skill/`.

- `SKILL.md`, short: when to use it, the setup check, the reply contract, the rules (uncertain, gates, consent, failures, addressing), and a one-line index of families pointing at the reference files.
- `references/surface.md`, `references/ui.md`, `references/audio.md`, `references/hear.md`: per family, the verbs with what each returns and its gate kind, worked examples. Exact arguments: `sf help`.
- `references/glossary.md`: copied from `CONTEXT.md` at package build time, so the agent and the musician share words.

The package also ships the extension (`extensions/sharpfive.ts`). The binary installs separately; the setup check in the skill tells pi how to detect its absence and what to tell the musician.

## 10. Out of this spec

The AU front-end (#21). An MCP wrapper (possible later). Controller and pitch-bend editing (map fog). The handshake responder (#27). The FETCH and BUILD tools themselves (gates fixed here, tools in their own tickets).

## 11. Facts this spec rests on

Logic Pro 11.2, macOS 26.7, prototypes of 2026-10-11 (branches `prototype/*`, unmerged by design). pi docs fetched 2026-10-11 (`research/pi-extension-idiom.md`): skills follow the Agent Skills spec with name and description loaded at startup and the body on demand; extensions hook `tool_call` (may block, may call `ctx.ui.confirm`), `before_agent_start` (may append to the system prompt) and `pi.sendMessage` (push into the loop); one package ships extensions, skills and prompts; MCP is built in since pi 0.99.0. `sf` replaced `+5` as the command name on 2026-10-15 (#40): a leading `+` is an option toggle under `sh -c`.
