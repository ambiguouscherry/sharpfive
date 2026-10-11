# EDIT limb contract: the bridge daemon and its tool surface

Resolves [Grilling: EDIT limb contract](https://github.com/ambiguouscherry/sharpfive/issues/25), 2026-10-11. Input for the tool-schemas grilling (#11). Builds on the MCU handshake (#5), v-pot (#6), MIDI write (#8), and locate (#26) prototypes. Vocabulary per [CONTEXT.md](../CONTEXT.md).

## 1. Shape

- **One long-lived process, the bridge daemon**, owns every CoreMIDI endpoint sharpfive presents to Logic: the Mackie Control source/destination pair (pinned unique IDs 2052752067 / -878604149) and the "Sharpfive Notes" source (pinned 1337420001). EDIT and WRITE are tool families on the same daemon; they share transport state, so they share a process. See [ADR 0001](../docs/adr/0001-one-bridge-daemon-owns-the-surface.md).
- **Stateless CLI commands** talk to the daemon over a local Unix socket. pi calls the CLI. The CLI never touches MIDI.
- **One Swift binary** ships both: `sf daemon` runs the daemon; every verb is a subcommand (`sf select "Inst 1"`). No runtime to install for a user. The socket protocol is language-neutral, so Python scripts can speak to the daemon directly for experiments without being part of the product. See [ADR 0002](../docs/adr/0002-single-swift-binary-for-daemon-and-cli.md).
- **Lifecycle**: launchd starts the daemon at login and restarts it if it dies. A CLI call that finds no daemon starts one. Manual start remains possible.

## 2. Protocol

- Unix socket, newline-delimited JSON. One request line, one reply line. A `state` request returns the full parsed model. A `watch` request turns the connection into an event stream (state changes, LCD settled, transport changes).
- Every reply carries the daemon's view *after* the action, not an assumption. See §5.
- An MCP wrapper over the same socket is possible later; it is not the default pattern (map Notes).

## 3. State model (what `state` returns)

Parsed model is the API. Raw data stays reachable under `raw` for debugging and parser work.

- `connection`: `{connected, lastTrafficAt, hint}`. `connected: false` with a setup hint when Logic stays silent after the daemon starts.
- `surface`: `bank`, eight `strips[]` each `{name (6-char), colour (SysEx cmd 72), selected, mute, solo, arm, fader (14-bit + dB as shown), ring, meter}`. Meters update ~100 ms and are non-zero only while the strip makes sound.
- `assignmentMode`: parsed from the assignment display. Known values: track, pan, send, instrument-list (`IN`), plugin-list (`P<slot>`), plugin-edit (`P<slot>.`).
- `pluginEdit` (when in plugin-edit): `{strip, slot, page: {n, m}, cells[8]: {abbrev, fullName?, unit?, value, kind}}` where `kind` is `continuous` (number + unit) or `discrete` (word or list item), inferred from the value cell.
- `settled`: false while a transient overlay is on the LCD (about 2 s after a touch or page change), true once the steady text is back (debounce ~130 ms after the last LCD write).
- `transport`: `{playing, scrubbing, recordLed, countIn, cycle, replace, drop, marker, position: {bar, beat, division, tick}}`. `playing` is false while `scrubbing` is true even though Logic lights PLAY. There is **no `recording` boolean**: the RECORD LED lit in 1 of 4 recordings. `recordLed` is exposed as observed; PLAY on plus CLICK on after a RECORD press is the usable tell.
- `directory`: all tracks in the project, `{index, name, colour, mute, solo, arm}`, built on connect by stepping the banks (~100 ms per bank). Per-track `slots[]` (instrument, inserts) are read on demand and cached; a `scan` verb fills every track.
- `raw`: 2×56 LCD framebuffer, assignment chars and dots, timecode digits, ring values, fader positions, last SysEx.

## 4. Transients

Transients are a source of facts, not noise. The daemon reads them and merges what they carry into the model (full parameter name, unit, page count) while cells keep their steady-state values. A `learn` verb touches each v-pot on each page once (~1 s per touch) to collect every full name for a plugin; results are cached per plugin name and Logic version. Shipped tables for Logic stock plugins are the warm cache; live learning fills gaps and covers third-party plugins.

## 5. Writes and readback

- **Fail-closed, synchronous.** Every write blocks until the expected echo lands or a timeout passes (feedback normally arrives in 5–30 ms; LCD settles ~130 ms after the last write). Reply: `{status: confirmed | uncertain | failed, requested, observed, settledAfterMs}`. A write with no echo in time is `uncertain`, never assumed.
- **Parameter set**: continuous parameters use FLIP (faders become absolute 14-bit for the page's eight parameters; exact set in one message). Discrete parameters use v-pot ticks (one tick is exactly one step; magnitude n is n steps; no acceleration). `nudge ±n` is public for "a bit more" language.
- **Locate** uses jog ticks at ≥ 80 ms spacing (one bar each, closed-loop against the beats display, ~10 bars/s) and SCRUB ticks at ≥ 300 ms spacing for beats (1/32 beat per tick). Faster ticks are accelerated by Logic and are non-deterministic; the daemon rate-limits.
- **Notes** are sent with CoreMIDI host-time stamps; a whole phrase queues in one call (tested 8 s ahead). Record start snaps down to the bar with a one-bar count-in. Overdubbing merges into an existing region by default; with REPLACE on, the recorded span (until STOP) replaces.

## 6. Addressing

Names in, indices out. Tools accept a track name (matched against the scribble strip, case-insensitive, 6-char prefix), a plugin name as Logic lists it, and a parameter full-or-abbreviated name. The daemon resolves to strip / slot / page / cell, banks left or right to find a track outside the current eight, and reports the resolved indices in every reply.

## 7. Verbs

| Verb | Notes | Gated |
|---|---|---|
| `state`, `raw`, `watch` | read-only | no |
| `tracks`, `scan` | directory; `scan` reads every slot | no |
| `select <track>`, `bank <±n>` | | no |
| `fader set/get`, `pan`, `mute`, `solo`, `arm` | | no |
| `plugin list` | plugins Logic offers (v-pot scroll of the list; full names on the LCD) | no |
| `plugin insert <track> <slot> <name>` | slot = `inst` or 1..n; same mechanic for instruments (INST) and effects (PLUG-IN) | yes if the slot is occupied (replace) |
| `plugin inventory <track>` | slots on one track | no |
| `plugin remove`, `plugin bypass` | **unverified**: no prototype or research covers them | yes |
| `param list <track> <slot>` | | no |
| `param get/set/nudge` | §5 | no |
| `learn <track> <slot>` | §4 | no |
| `transport play/stop` | | no |
| `transport record` | writes a region | yes |
| `locate <bar> [beat]` | proven by #26 | no |
| `cycle`, `replace`, `drop` | toggles with LED feedback; cycle *range* cannot be set from the surface | no |
| `notes send` | WRITE; stamped phrase | no (record is the gate) |

Gating: the daemon does not ask the musician. A gated call without `--confirm` returns `status: gated` and what it would do; pi asks, then calls again with `--confirm`. FETCH and BUILD gates are defined in the glossary and are not part of this contract.

## 8. Side effects the musician will see

Reading a track's slots or parameters selects that track on the surface, so Logic's selection follows and the plug-in window may open. The daemon restores the previous selection after a read it initiated. Reads of the already-selected track are silent. Logic's MIDI-in activity light flickers with surface traffic (cosmetic).

## 9. Rebinding and coexistence

- Pinned CoreMIDI unique IDs plus a one-time manual install (Logic → Control Surfaces → Setup → Install → Mackie Control, both ports = the daemon's endpoints) are the proven path on Logic 11.2. The daemon reports `connected: false` with that hint when Logic is silent.
- The handshake responder (auto-detect on a fresh Logic) is a task ticket, not part of this contract.
- The surface registers under its own name ("sharpfive"). Other control surfaces may coexist; the setup doc says to keep sharpfive in its own control surface group so hardware does not fight it.

## 10. Out of this contract

- **Screen access.** The daemon works blind. Screenshots or accessibility reads are a separate LISTEN limb, designed with the UI-scripting (#9) and interface (#21) tickets; a help, never a requirement.
- **Cycle locators, markers, count-in and record-snap settings**: not reachable from the surface.
- **Region contents**: the surface cannot read notes back; see the round-trip ticket (#10).

## 11. Facts this spec rests on

Logic Pro 11.2, macOS 26.7, 2026-10-11 prototypes on branches `prototype/mcu-handshake`, `prototype/mcu-vpot`, `prototype/midi-write`, `prototype/mcu-locate` (unmerged by design; primary sources).
