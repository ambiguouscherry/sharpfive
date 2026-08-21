# Research: Does Logic Pro 11.2 expose a public scripting/automation API?

**Ticket:** [#2](https://github.com/ambiguouscherry/sharpfive/issues/2)
**Date:** 2026-08-21
**Answer: No — the constraint holds.** Logic Pro 11.2 has no public scripting or automation API that can read or drive the application (projects, tracks, regions, mixer, transport) programmatically. The surfaces that do exist are narrow and none of them changes the bridge architecture.

## 1. AppleScript / Scripting Bridge — effectively none

Checked the installed app directly (`/Applications/Logic Pro.app`, `CFBundleShortVersionString` = **11.2**):

- `Info.plist` has `NSAppleScriptEnabled = 1`, but **no `OSAScriptingDefinition` key** and **no `.sdef` file anywhere in the bundle** (`find .../Contents -name "*.sdef"` returns nothing).
- With `NSAppleScriptEnabled` set but no sdef, Cocoa Scripting serves only the **default Standard Suite**: `activate`, `open`, `quit`, and generic `window` objects (name, bounds, miniaturize, close). There is **no Logic-specific terminology** — no tracks, regions, transport, mixer, project, or export commands.
- Consequently Scripting Bridge / JXA get the same empty surface: nothing beyond launching the app and poking at window geometry.

`sdef "/Applications/Logic Pro.app"` requires full Xcode on this machine, but the absence of any `.sdef` resource and the `OSAScriptingDefinition` key in the bundle is the same primary evidence.

## 2. Scripter (MIDI FX plug-in) — MIDI-stream-local only

Apple's Scripter documentation ([Use Scripter](https://support.apple.com/guide/logicpro/use-scripter-lgce728c68f6/mac), [HandleMIDI](https://support.apple.com/guide/logicpro/handlemidi-function-lgce12088271/mac), [ProcessMIDI](https://support.apple.com/guide/logicpro/processmidi-function-lgce225e4d89/mac)) shows a JavaScript environment whose entire scope is the **MIDI event stream of the one channel strip it is inserted on**:

- `HandleMIDI(event)` — process/transform incoming MIDI events on that strip.
- `ProcessMIDI()` + `TimingInfo` — per-audio-block callback with **read-only** tempo/beat/playhead/cycle info.
- `GetParameter`/`SetParameter`, `PluginParameters` — the plug-in's own UI controls only.
- No object for tracks, regions, mixer, project data, or transport control; no file system or network I/O. Scripter can *observe* the playhead but cannot start/stop it, create content, or touch anything outside its insert slot.

## 3. Control-surface / OSC layer — remote control, not an API

Logic has supported OSC in its control-surface layer since 9.1.2 and still does in 11.x ([Control surface special parameters](https://support.apple.com/en-lk/guide/logicpro/ctls718de3eb/mac), [OSC message paths](https://support.apple.com/guide/logicpro/osc-message-paths-ctlsf67f4bdc/mac)):

- OSC devices (UDP/IPv4 only) and MIDI control surfaces (Mackie Control protocol, Logic Remote) map onto Logic's **controller-assignment model**: transport start/stop/record, fader/pan/send levels, plug-in parameter banks, channel select/mute/solo.
- This is a *human control surface emulation*: state comes back as fader/LED-style feedback for whatever bank is in view. There is **no query/response data model** — no way to enumerate the project, read region contents, create tracks, insert plug-ins by name, edit MIDI data, or export audio.
- The control-surface plug-in SDK Apple mentions for third parties is private/undocumented (the bundled surface support lives in internal plug-ins); there is no public SDK download.

Useful for a bridge as a *transport/mixer remote-control channel*, but not as an automation API.

## 4. Anything new in Logic 11.x? No

The [Logic Pro for Mac 11 release notes](https://support.apple.com/en-us/126835) and [What's new in Logic Pro 11.2](https://support.apple.com/guide/logicpro/whats-new-in-logic-pro-112-lgcp02e40443/mac) list Flashback Capture, enhanced Stem Splitter (6 stems, presets, submixes), Writing Tools in Notepad, region gain normalization, and long mixer faders — **no scripting, automation, or API additions** anywhere in the 11.0–11.2 line.

## Implication for the bridge

Automation of Logic itself must continue to go through the existing indirect channels: UI-level automation (Accessibility API / System Events keystrokes — note the empty AppleScript dictionary means even System Events is driving menus/keys, not a data model), the control-surface/OSC layer for transport & mixer moves, Scripter/virtual-MIDI for note-stream manipulation, and file-level interchange (project/MIDI/audio files) for everything else. The architecture's load-bearing constraint stands.

## Sources

- Local inspection of `/Applications/Logic Pro.app` (v11.2): `Info.plist` keys, bundle `find` for `.sdef`.
- https://support.apple.com/guide/logicpro/use-scripter-lgce728c68f6/mac
- https://support.apple.com/guide/logicpro/handlemidi-function-lgce12088271/mac
- https://support.apple.com/guide/logicpro/processmidi-function-lgce225e4d89/mac
- https://support.apple.com/guide/logicpro/osc-message-paths-ctlsf67f4bdc/mac
- https://support.apple.com/en-lk/guide/logicpro/ctls718de3eb/mac
- https://support.apple.com/en-us/126835
- https://support.apple.com/guide/logicpro/whats-new-in-logic-pro-112-lgcp02e40443/mac
