# Handoff: Modded Pi (pi.dev) Agent Harness for Logic Pro X

## Project Goal
Mod the open-source **pi coding agent harness (pi.dev)** into a music agent that can **listen to**, **write**, and **edit** music in Logic Pro X — MIDI parts, audio, and effect/mix parameters. The agent brain is pi running in a terminal **on the same Mac as Logic**, extended with custom tools/skills/extensions that bridge into Logic.

## What pi is (context for the session)
- Minimal, aggressively extensible terminal agent harness by Earendil (MIT, TypeScript). `pi install` packages; extensions are TS modules with access to tools, commands, events, TUI.
- **No MCP by design** — the idiomatic pattern is **CLI tools with READMEs, packaged as skills** (progressive disclosure, loaded on demand). Build each Logic limb as a CLI tool + skill doc.
- Extensions can add tools, permission gates, custom compaction, dynamic context injection. AGENTS.md / SYSTEM.md control project instructions and system prompt.
- Four modes: interactive TUI, print/JSON, RPC (stdin/stdout JSON), SDK. RPC/SDK matter if we later embed the agent elsewhere (e.g., an AU UI chatting with a pi session).

## Core Constraint (settled, don't re-litigate)
- Logic Pro has **no public scripting/automation API** (unlike Reaper/Ableton).
- A plugin (AU) is sandboxed in the host: it **cannot** create tracks, insert effects, edit regions, or touch other plugins' parameters. No API surface exists for project-level ops, even in-process.
- Logic loads **AU only**, not VST (JUCE targeting AU is fine).
- Therefore: pure-plugin harness is a dead end. Architecture = **pi brain on the Mac + thin bridges into Logic**, each bridge exposed to pi as a CLI tool/skill.

## Architecture Thesis
**Music flows over local wire protocols (CoreMIDI, audio taps); structure flows through accessibility/key-command scripting.** Since pi runs on the Mac, everything is local: IAC buses, CoreMIDI virtual ports, localhost sockets, AppleScript/AXUIElement — all reachable from CLI tools that pi invokes with its bash tool or as registered tools.

## The Limbs → pi skills/tools

### 1. Brain: modded pi
- Custom AGENTS.md/SYSTEM.md establishing the music-agent role, Logic conventions, safety rules.
- Extension for **permission gates** on destructive ops (pi has no built-in permission popups — build the confirmation flow as an extension, per pi's own guidance).
- Skills for each limb below; possibly an extension injecting live Logic state (selected track, transport) into context each turn (pi supports dynamic context injection).

### 2. MIDI I/O tool (`logic-midi`)
- CLI tool using CoreMIDI: create virtual source/destination or use IAC bus.
- **Write:** stream MIDI sequences into record-armed tracks; send mapped CC automation. Accept note lists / MIDI files as input.
- **Listen (MIDI):** subscribe to an IAC bus Logic routes tracks to; capture note-level ground truth.
- Node has decent CoreMIDI bindings (node-midi); or Swift/Python helper binaries.

### 3. Control-surface tool (`logic-mcu`)
- Emulates a **Mackie Control** over a CoreMIDI virtual port Logic is configured to see as a control surface.
- Covers: faders, pans, sends, plugin parameters on selected track, bypass, transport, track selection, mute/solo/arm, some track creation.
- **Bidirectional**: parse MCU feedback (Logic reports fader/param state) → read-modify-write loops and cheap state readback.
- Highest-leverage single tool for the EDIT verb (parameters/mix).

### 4. Audio-listen tool (`logic-audio-tap`)
- Zero-code start: **AUNetSend** on master/stems → local receiver process → PCM to disk/stream → analysis tools (levels, spectrum, or ML model) that pi invokes.
- Later: custom thin AU FX streaming PCM over localhost socket for lower latency/multi-tap.
- Companion analysis CLI: `analyze-audio <file|stream>` returning structured JSON (loudness, spectral features, transcription/classification hooks).

### 5. UI-scripting tool (`logic-ui`)
- AXUIElement + AppleScript System Events + **custom Logic key-command set** so actions are deterministic keystrokes, not fragile menu traversal.
- Covers protocol-less actions: insert a specific plugin, name tracks, create tracks of a given type, region ops (select/delete), trigger MIDI file import, dialog handling.
- Requires Accessibility permission for the terminal/pi process.

### 6. Perception/readback
- Verify, don't fire blind: accessibility-tree reads (`logic-ui inspect`), screenshots (`screencapture` + vision model via pi), MCU feedback (cleanest channel where available).

### 7. File round-trip (`logic-files`)
- .mid write + scripted import for bulk composition; region export for reading existing parts.
- Logic project bundle is undocumented — read-only exploration at most; never write.

## Leverage Ranking by Verb

### LISTEN
- Top: AUNetSend → local receiver → analysis CLI (cheapest high-value limb).
- MIDI listen via IAC routing (note-level ground truth without audio ML).

### WRITE
- Top: MIDI streaming into record-armed tracks via `logic-midi`.
- Second: .mid file + scripted import (better throughput for full arrangements).
- Audio writing: render → import file. Don't attempt real-time audio streaming into Logic.

### EDIT
- Parameters/mix: `logic-mcu` (one protocol, huge coverage, bidirectional).
- **Note editing in existing regions: no protocol exists.** Use the **round-trip**: export/read region as MIDI (file export, or play it out an IAC bus while capturing) → agent edits the sequence → replace region (delete + re-import/re-record) via `logic-ui` glue. Converts "impossible" into two already-solved problems.

## Build Order (MVP)
1. `logic-midi` — CoreMIDI virtual ports/IAC: write + MIDI listen in one tool
2. `logic-mcu` — MCU emulation + feedback parsing: parameter edit + state readback
3. `logic-ui` — accessibility/key-command glue + custom key-command set
4. AUNetSend receiver + `analyze-audio` — audio listen
5. `logic-files` — .mid round-trip for bulk write and note editing
6. pi mods: skills/READMEs for each tool, AGENTS.md, permission-gate extension, optional dynamic-context extension for live Logic state

Custom AU plugin (audio taps, in-DAW generative MIDI synced to host transport, in-Logic UI) is the later upgrade from "robot using Logic" to a system that plays and listens in real time.

## Open Questions / Next Steps
- Language per tool: Node (shares pi's ecosystem, node-midi) vs. Swift helpers (native CoreMIDI/AX) — likely Swift binaries wrapped in Node CLIs.
- Define the exact MCU message subset + feedback parsing (v-pot/param pages for plugin control are the fiddly part).
- Verify AUNetSend's network format and receiver options; fallback is a minimal custom tap AU.
- Design the round-trip note-edit flow precisely (export mechanism, region replacement semantics, undo safety).
- Spec the custom Logic key-command set and ship it as an importable .logicx key-commands file.
- Tool schema/skill docs: `send_midi`, `set_param`, `read_meters`, `import_midi_file`, `ui_action`, `inspect_ui` — with permission gates on destructive ops.
- Survey existing Logic automation projects (incl. "Logic Pro MCP server" experiments) for reusable pieces — note pi is MCP-less, so port logic into CLI tools rather than MCP servers.
