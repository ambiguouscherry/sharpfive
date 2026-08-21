# MCU protocol subset and Logic Pro control-surface behavior

*Research document for the sharpfive/pi project (virtual CoreMIDI port presenting as a Mackie Control to Logic Pro, driven by CLI tools). Resolves issue #3.*

All byte values are hex unless noted. The primary byte-level reference is the reverse-engineered MCU protocol documentation in [NicoG60/TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md) (itself derived from the Logic Control manual's MIDI implementation appendix); behavioral claims about Logic Pro come from Apple's [Logic Pro Control Surfaces Support guide](https://support.apple.com/guide/logicpro-css/mackie-control-overview-ctls7222820e/mac) (also available as a [single PDF](https://help.apple.com/pdf/logicpromac-css/en_US/logic-pro-mac-control-surfaces-support-guide.pdf)); DAW-side implementation evidence comes from [Ardour's Mackie surface code](https://github.com/Ardour/ardour/tree/master/libs/surfaces/mackie).

---

## 1. Handshake, device inquiry, and auto-detection

### 1.1 SysEx framing

Every MCU SysEx message is framed as:

```
F0 00 00 66 <dev> <cmd> [data...] F7
```

- `00 00 66` = Mackie Designs manufacturer ID.
- `<dev>` = `14` for a Mackie Control / MCU main unit, `15` for an XT (extender). ([TouchMCU protocol doc](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md))

### 1.2 The discovery sequence

The classic Logic Control / MCU discovery flow, as documented in TouchMCU and implemented DAW-side in Ardour:

| Step | Direction | Message |
|---|---|---|
| 1 | Host → device | **Device Query**: `F0 00 00 66 14 00 F7` (command `00`, no payload) |
| 2 | Device → host | **Host Connection Query**: `F0 00 00 66 14 01 ss ss ss ss ss ss ss cc cc cc cc F7` — 7-byte serial + 4-byte random challenge (18 bytes total on the wire; Ardour's `surface.cc` checks `bytes.size() != 18`) |
| 3 | Host → device | **Host Connection Reply**: `F0 00 00 66 14 02 ss...ss rr rr rr rr F7` — same serial + 4-byte response code computed from the challenge |
| 4 | Device → host | **Connection Confirmation**: command `03` + serial (or `04` = connection error) |

The response-code algorithm (from the Logic Control manual, reproduced in TouchMCU):

```
r[0] = 0x7F & (c[0] + (c[1] ^ 0x0A) - c[3])
r[1] = 0x7F & ((c[2] >> 4) ^ (c[0] + c[3]))
r[2] = 0x7F & (c[3] - (c[2] << 2) ^ (c[0] | c[1]))
r[3] = 0x7F & (c[1] - c[2] + (0xF0 ^ (c[3] << 4)))
```

([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md); the same flow is documented in the [Understanding Mackie Control Protocol wiki](https://github.com/Silhm/bcf-scribble-strips/wiki/Understanding-Mackie-Control-Protocol) and the original Logic Control hardware manual, `LogicControl_EN.pdf`, whose appendix is the canonical MIDI implementation chart — mirrored widely, e.g. on stash.reaper.fm as the "MCU MIDI map".)

### 1.3 Does Logic actually require the handshake?

Two paths exist, and **the handshake is only needed for auto-detection, not for operation**:

- **Auto-detection**: "Any powered Mackie Control unit connected to your system is automatically detected when you open Logic Pro" ([Apple, Mackie Control overview](https://support.apple.com/guide/logicpro-css/mackie-control-overview-ctls7222820e/mac)). At launch Logic broadcasts the Device Query on its MIDI outputs; a device that answers with a well-formed Host Connection Query (serial + challenge) gets installed automatically with the correct ports. For a virtual port to be *auto*-detected, it must answer command `00` with command `01` and accept the `02` reply.
- **Manual installation**: Logic's Control Surfaces Setup (Logic Pro → Control Surfaces → Setup → New → Install… → "Mackie Designs / Mackie Control / Logic Control") lets the user add the surface manually and assign the MIDI In/Out ports; Apple documents this manual add-with-port-assignment flow for emulation devices ([Apple, control-surface device parameters](https://support.apple.com/guide/logicpro/device-parameters-ctls718dd91b/mac)). Once installed this way, Logic starts driving the surface (LCD writes, fader echo, LEDs) without any challenge-response. This is exactly how existing virtual-MCU projects work: [MongLong0214/logic-pro-mcp](https://github.com/MongLong0214/logic-pro-mcp) creates a virtual port (`LogicProMCP-MCU-Internal`) and instructs the user to **register it manually** in Control Surfaces Setup — no handshake implementation is required or documented there.
- Corroborating DAW-side evidence: Ardour's `surface.cc` supports devices flagged `no_handshake()` — the surface is simply "turned on" upon receiving *any* fader/note/CC traffic — and notes "there are no known cases of the handshake process failing" ([ardour/libs/surfaces/mackie/surface.cc](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.cc)).

**Recommendation for sharpfive**: implement the responder anyway (it is ~20 lines: reply to `F0 00 00 66 14 00 F7` with a fixed fake serial and answer the host reply with confirmation `03`), because it makes Logic auto-install the surface with zero user setup; but treat manual installation as the guaranteed fallback. Also parse and ignore/answer other host SysEx commands Logic may send: `13` (version request → reply `14` + version string), `0A` (transport-click config), `61` (faders to minimum), `62` (all LEDs off), `63` (reset). ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md))

---

## 2. Control messages the surface sends (device → Logic)

Everything below rides on **MIDI channel 1** (status bytes `9x`/`Bx`/`Ex` with n=0), except faders, which use the channel number to address the strip.

### 2.1 Faders — Pitch Bend, one MIDI channel per fader

| Strip | Message |
|---|---|
| Channels 1–8 | `E0`–`E7` `ll hh` (pitch bend on MIDI ch. 1–8) |
| Master | `E8 ll hh` (pitch bend on MIDI ch. 9) |

14-bit value `0`–`16383`: "0 being all the way down, and 16383 being top of the roof" ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)). Logic maps this across the fader's dB range (hardware is calibrated so that 0 dB sits at the printed mark).

**Touch sense**: real MCUs bracket fader moves with touch notes — Note On `90 68+n 7F` (touch) … `90 68+n 00` (release), notes `68`–`6F` for strips 1–8 and `70` for master ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)). Logic uses touch to punch touch/latch automation. A CLI emulator should send touch-on → pitch bend(s) → touch-off around each programmatic fader move so automation modes behave correctly; for simple mixing Logic accepts bare pitch bend without touch.

### 2.2 V-Pots (rotary encoders) — relative CCs

- **Rotation**: `B0 10+n vv` (CC `10`–`17` for strips 1–8). Value is sign-magnitude 7-bit relative: `01`–`07` = clockwise by 1–n ticks, `41`–`47` = counter-clockwise (bit 6 = direction, low bits = speed/steps). E.g. `B0 10 01` = V-Pot 1 one click right; `B0 10 41` = one click left. ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md); Ardour parses "bit 6 gives the sign" in `surface.cc`.)
- **V-Pot press**: Note On, notes `20`–`27` for strips 1–8, velocity `7F` press / `00` release. In Logic, a press "sets a default parameter value… or switches between two parameter values (on/off)", and confirms selections such as inserting a plug-in ([Apple, V-Pots](https://support.apple.com/guide/logicpro-css/v-pots-ctls722275cd/mac)).
- Logic's speed handling: "The faster you turn the V-Pot, the quicker it changes values" ([Apple, V-Pots](https://support.apple.com/guide/logicpro-css/v-pots-ctls722275cd/mac)) — so a CLI tool can send multi-tick values (`02`, `03`…) or repeated single ticks for coarse moves.
- **Sends**: there is no dedicated "send knob" message — sends are edited via V-Pots after pressing the **Send** assignment button (section 4).

### 2.3 Buttons — Note On/Off on channel 1

All buttons are `90 nn 7F` (press) / `90 nn 00` (release). Full map from [TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md):

**Per-strip buttons** (n = strip 0–7):

| Function | Notes |
|---|---|
| REC/RDY (rec-arm) | `00`–`07` |
| SOLO | `08`–`0F` |
| MUTE | `10`–`17` |
| SELECT | `18`–`1F` |
| V-Pot press | `20`–`27` |
| Fader touch | `68`–`6F` (+ `70` master) |

**Assignment / navigation / global:**

| Function | Note | Function | Note |
|---|---|---|---|
| TRACK | `28` | BANK ◀ | `2E` |
| SEND | `29` | BANK ▶ | `2F` |
| PAN/SURROUND | `2A` | CHANNEL ◀ | `30` |
| PLUG-IN | `2B` | CHANNEL ▶ | `31` |
| EQ | `2C` | FLIP | `32` |
| INSTRUMENT | `2D` | GLOBAL VIEW | `33` |

**Display/mode, function keys, view groups, modifiers, automation, utility:**

| Function | Note(s) |
|---|---|
| NAME/VALUE | `34` |
| SMPTE/BEATS | `35` |
| F1–F8 | `36`–`3D` |
| Global-view group buttons (MIDI Tracks, Inputs, Audio Tracks, Audio Instrument, Aux, Busses, Outputs, User) | `3E`–`45` |
| Modifiers: SHIFT `46`, OPTION `47`, CONTROL `48`, CMD/ALT `49` | |
| Automation: READ/OFF `4A`, WRITE `4B`, TRIM `4C`, TOUCH `4D`, LATCH `4E`, GROUP `4F` | |
| Utility: SAVE `50`, UNDO `51`, CANCEL `52`, ENTER `53` | |
| MARKER `54`, NUDGE `55`, CYCLE `56`, DROP `57`, REPLACE `58`, CLICK `59`, SOLO(global) `5A` | |

**Transport and navigation:**

| Function | Note |
|---|---|
| REWIND | `5B` |
| FAST FWD | `5C` |
| STOP | `5D` |
| PLAY | `5E` |
| RECORD | `5F` |
| Cursor Up/Down/Left/Right | `60`/`61`/`62`/`63` |
| ZOOM | `64` |
| SCRUB | `65` |

**Jog wheel**: `B0 3C vv` — same sign-magnitude relative encoding as V-Pots (`01`… clockwise, `41`… counter-clockwise). External footswitch/expression input is CC `2E` region (external controller `B0 2E vv`). ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md))

---

## 3. Feedback Logic emits (Logic → surface) and how to parse it

This is the valuable half for sharpfive: a CLI tool that reads Logic's state (track names, fader positions, pan values, plugin parameter names/values, transport state) does so purely by parsing this stream.

### 3.1 Fader position echo — Pitch Bend

Logic echoes every fader's current position (motor drive) as pitch bend on channels 1–9, same encoding as §2.1. After banking, selecting, or loading a project, Logic re-sends all nine. Parse: `value = (hh << 7) | ll`, strip = MIDI channel. ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md); [MongLong0214/logic-pro-mcp](https://github.com/MongLong0214/logic-pro-mcp) uses this echo as its readback-verification channel — "MCU echo" for `set_master_volume`.)

### 3.2 LED states — Note On velocity

Logic drives every button LED with the same note numbers as §2.3: velocity `7F` = on, `01` = flashing, `00` = off ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)). So transport state = watch notes `5B`–`5F`; rec/solo/mute/select per strip = notes `00`–`1F`; automation-mode LEDs = `4A`–`4F`. Display-adjacent LEDs: SMPTE `71`, BEATS `72`, RUDE SOLO `73`, RELAY CLICK `76`.

### 3.3 V-Pot LED rings — CC `30`–`37`

`B0 30+n vv` for strips 1–8. Value bit layout (from [TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)):

```
b7 = 0 | b6 = center-LED on/off | b5..b4 = mode | b3..b0 = value (0-11)
```

Modes: `00` single dot, `01` boost/cut (fill from center — used for pan), `10` wrap (fill from left — used for levels/sends), `11` spread (widen from center — used for Q/spread). Parsing ring feedback gives you a coarse (12-step) readout of pan/send/plugin-parameter values; the precise value text comes from the LCD (§3.4).

### 3.4 Scribble strip LCD — SysEx `12`

```
F0 00 00 66 14 12 <offset> <ASCII bytes...> F7
```

- The display is 2×56 characters (2×55 visible on original hardware): offset `00`–`37` = top row, `38`–`6F` = bottom row ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)).
- Each channel strip owns a 7-character cell: strip n's top cell starts at offset `n*7`, bottom cell at `0x38 + n*7`. Logic writes 6 characters + a space separator per cell in practice.
- Logic sends partial updates at arbitrary offsets and lengths — a parser must maintain a 112-byte framebuffer, apply each SysEx as a splice at `offset`, and re-segment into 7-char cells to recover per-strip name/value strings.
- The **NAME/VALUE** button (note `34`) toggles what Logic paints: names vs. values ([Apple, plug-in edit view](https://support.apple.com/guide/logicpro-css/plug-in-edit-view-ctls72227232/mac)). In value mode Logic includes units ("Hz, dB, etc.") when they fit.
- Extenders get the same message with device ID `15`.

### 3.5 Timecode and Assignment 7-segment displays — CC `40`–`4B`

`B0 4x vv` (Logic sends these on channel 1; the spec also allows `BF`):

- CC `40`–`49` = the 10-digit SMPTE/beats display, **right-to-left** (CC `40` is the rightmost digit).
- CC `4A`–`4B` = the 2-digit **Assignment** display (shows Logic's current assignment mode, e.g. "Pn", "P1."–"P8." for insert slots in plug-in mode).
- Value encoding: bits 0–5 select the character (a 64-glyph set: `30`+digit for `0-9`, letters at `01`–`1A`, space `20`), bit 6 = decimal point on. ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md); Apple confirms the assignment display shows "a two-digit abbreviation of the assignment type" — [assignment buttons overview](https://support.apple.com/guide/logicpro-css/assignment-buttons-overview-ctls72228bb1/mac).)

Parsing the timecode display is the cleanest way for a CLI tool to read the playhead position, in either SMPTE or bars/beats depending on the SMPTE/BEATS toggle (note `35`).

### 3.6 Level meters — Channel Pressure

`D0 vv` where the high nibble of `vv` = strip (0–7) and low nibble = level: `0` = signal < −60 dB, `1`–`C` rising levels, `E` = set overload, `F` = clear overload ([TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)). Logic streams these continuously during playback for the visible bank. Host SysEx commands `20` (per-channel meter mode) and `21` (global LCD-metering enable) configure meter behavior on real hardware; an emulator can ignore them but should swallow them silently.

---

## 4. Assignment modes and plug-in parameter control (the fiddly part)

The six assignment buttons (`28`–`2D`) put the 8 V-Pots (and, after FLIP, the faders) into different parameter layers. Each has a **Mixer view** (one parameter type across 8 channels) and a **Channel view** (many parameters of the *selected* channel across the 8 strips); Logic shows the mode as a two-digit code on the assignment display ([Apple, assignment buttons overview](https://support.apple.com/guide/logicpro-css/assignment-buttons-overview-ctls72228bb1/mac), [assignment views](https://support.apple.com/guide/logicpro-css/assignment-views-ctls7222656b/mac)).

- **TRACK** (`28`): volume/pan/format/input/output per strip.
- **PAN/SURROUND** (`2A`): V-Pots = pan (this is the default mode; ring mode = boost/cut).
- **SEND** (`29`): mixer view = one send slot across channels; channel view = all sends of selected track (destination/level/position/mute per slot).
- **EQ** (`2C`): channel EQ bands of the selected track.
- **INSTRUMENT** (`2D`): instrument plug-in parameters of the selected track.
- **PLUG-IN** (`2B`): two-level navigation, per [Apple's plug-in edit view page](https://support.apple.com/guide/logicpro-css/plug-in-edit-view-ctls72227232/mac):
  1. **Selection view** — after pressing PLUG-IN, the LCD shows the plug-in name in each insert slot (mixer view: slot x across channels; channel view: slots of selected track). Rotating a V-Pot scrolls the plug-in list for that slot; **pressing the V-Pot** confirms/inserts and drops into…
  2. **Edit view** — the assignment display shows `P1.`–`P8.` for the insert slot; the LCD shows (name mode) channel name, insert number, plug-in name, *current parameter page and total pages* on the top row and parameter names in the 7-char cells; NAME/VALUE (`34`) switches to value mode with units. V-Pot rotate edits, V-Pot press sets default / toggles binary parameters.
  3. **Paging**: parameters come in pages of 8. **Cursor Left/Right (`62`/`63`) switch parameter pages**; holding CMD/ALT (`49`) makes them shift by *one parameter* instead of a page. **Cursor Up/Down (`60`/`61`) switch the insert slot (1–15)** while in edit view. (Bank/Channel buttons `2E`–`31` keep their track-banking meaning.)
  4. Leaving edit view (press PLUG-IN again or select another mode) closes the plug-in window Logic opened on screen.

**Implication for sharpfive CLI tools**: "set plugin parameter X on track Y" decomposes into a deterministic message sequence — SELECT track (note `18+n` for a visible strip, banking first with `2E/2F` if needed) → PLUG-IN (`2B`) → cursor up/down to slot → V-Pot press to enter edit → cursor-right page-stepping while *parsing the LCD top row for "page i/j" and the cells for parameter names* → rotate the matching V-Pot. The LCD framebuffer parser (§3.4) is therefore the core enabling component; parameter identity is only available as 6–7-char truncated names, so fuzzy matching is required. FLIP (`32`) mirrors V-Pot assignments onto the motor faders, which lets you *write* fine-grained parameter values via 14-bit pitch bend instead of encoder ticks — a useful trick for precise CLI sets, and Logic echoes the value back on the same pitch-bend channel for verification.

---

## 5. Survey of open-source implementations

| Project | What it implements | Language | License | Portable to sharpfive? |
|---|---|---|---|---|
| [NicoG60/TouchMCU](https://github.com/NicoG60/TouchMCU) | Full MCU surface for TouchOSC; `doc/mackie_control_protocol.md` is the best free byte-level spec (handshake algorithm, all note/CC maps, LCD, 7-seg, meters) | TouchOSC/Lua + Python generator | GPL-3.0 | Use the **doc** freely as a spec; code is GPL |
| [Ardour libs/surfaces/mackie](https://github.com/Ardour/ardour/tree/master/libs/surfaces/mackie) | Complete *host-side* MCU implementation: device query/handshake, `no_handshake` devices, faders, pots (sign-bit parsing), LCD, meters, device profiles | C++ | GPL-2.0+ | Best reference for exact message semantics from the DAW's perspective (sharpfive plays the *device* side — mirror image) |
| [MongLong0214/logic-pro-mcp](https://github.com/MongLong0214/logic-pro-mcp) | Virtual CoreMIDI port registered manually as MCU in Logic; fader set with pitch-bend echo readback ("fail-closed" confirmed/uncertain/failed results); transport; LED/meter parsing | Swift 6 | MIT | **Most directly portable**: the CoreMIDI virtual-source/destination creation, MCU echo-verification pattern, and manual-registration setup flow all transfer to CLI tools; MIT-licensed |
| [koltyj/logic-pro-mcp](https://github.com/koltyj/logic-pro-mcp) | Multi-channel Logic control (MCU + Accessibility + AppleScript + CGEvent + OSC) with routing/fallback; sub-ms transport via MCU | Swift/mixed | see repo | The channel-routing idea (MCU for transport/mixer, AX for what MCU can't reach) is worth copying architecturally |
| [aircrack-ng-debug/Logic-Pro-MCP](https://github.com/aircrack-ng-debug/Logic-Pro-MCP), [kiki830621/che-logic-pro-mcp](https://github.com/kiki830621/che-logic-pro-mcp) | AppleScript + virtual MIDI (notes/CC/MMC), lighter MCU coverage | Python/mixed | see repos | Mostly demonstrates the non-MCU fallbacks |
| [Silhm/bcf-scribble-strips wiki](https://github.com/Silhm/bcf-scribble-strips/wiki/Understanding-Mackie-Control-Protocol) | Prose explanation of MCP framing, SysEx header, LCD | wiki | — | Secondary confirmation of the spec |
| Bitfocus [companion-module-behringer-x-touch](https://github.com/bitfocus/companion-module-behringer-xtouch) / Xctl docs | X-Touch's Xctl variant + MCU mode | JS | MIT-family | Confirms MCU message set is what X-Touch-class hardware speaks; not Logic-specific |
| REAPER CSI / stash.reaper.fm "MCU MIDI map" PDF | Community-standard MCU byte chart (same content as the Logic Control manual appendix, `LogicControl_EN.pdf`) | PDF | — | Cross-check reference |

---

## 6. Portable logic / recommendations for sharpfive

1. **Create one virtual CoreMIDI source + destination pair** named something recognizable (e.g. "sharpfive MCU"). Implement the §1.2 handshake responder (fixed serial, challenge→response formula above) so Logic auto-installs the surface at launch; document manual installation (Control Surfaces Setup → Install → Mackie Control) as the fallback that provably works without any handshake ([MongLong0214](https://github.com/MongLong0214/logic-pro-mcp), [Ardour `no_handshake`](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.cc)).
2. **Maintain surface state in a daemon, not per CLI invocation.** The valuable feedback (112-char LCD framebuffer, 9 fader positions, LED bitmap, timecode digits, meter nibbles) only makes sense accumulated over time. A small background process owning the CoreMIDI port and exposing state via a socket/file lets stateless CLI tools (`sf transport play`, `sf fader 3 -12.5dB`, `sf plugin set ...`, `sf lcd dump`) stay trivial. This mirrors MongLong's fail-closed echo-verification design, minus MCP.
3. **Write path**: transport = single notes `5B`–`5F`; faders = pitch bend (bracket with touch notes `68+n` for automation correctness); pan/sends/plugin params = relative CC ticks `10`–`17` — or FLIP (`32`) + pitch bend for precise absolute sets.
4. **Read path**: parse pitch-bend echo for levels; notes for LED/transport/mute/solo/arm state; CC `40`–`4B` for playhead + assignment mode; SysEx `12` splices into the LCD framebuffer for track names, parameter names and values (7-char cells, NAME/VALUE toggle via note `34`); `D0` pressure for meters.
5. **Plugin control** is a navigation state machine (§4): SELECT → PLUG-IN → slot via cursor up/down → V-Pot press → page with cursor left/right while reading page numbers and truncated parameter names off the LCD. Budget for fuzzy name matching and settle-time waits after each navigation step (Logic repaints the LCD asynchronously).
6. **Licensing**: keep TouchMCU/Ardour as *specifications only* (GPL); MongLong0214/logic-pro-mcp is MIT if actual code porting is wanted.

### Sources

- [TouchMCU Mackie Control protocol doc (NicoG60)](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)
- Apple Logic Pro Control Surfaces Support: [Mackie Control overview](https://support.apple.com/guide/logicpro-css/mackie-control-overview-ctls7222820e/mac), [Assignment buttons overview](https://support.apple.com/guide/logicpro-css/assignment-buttons-overview-ctls72228bb1/mac), [Assignment views](https://support.apple.com/guide/logicpro-css/assignment-views-ctls7222656b/mac), [V-Pots](https://support.apple.com/guide/logicpro-css/v-pots-ctls722275cd/mac), [Plug-in edit view](https://support.apple.com/guide/logicpro-css/plug-in-edit-view-ctls72227232/mac), [Displays overview](https://support.apple.com/guide/logicpro-css/displays-overview-ctls72226f72/mac), [Device parameters](https://support.apple.com/guide/logicpro/device-parameters-ctls718dd91b/mac), [full guide PDF](https://help.apple.com/pdf/logicpromac-css/en_US/logic-pro-mac-control-surfaces-support-guide.pdf)
- [Ardour Mackie surface source (`surface.cc`)](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.cc) and [Ardour manual, Mackie/Logic Control devices](https://manual.ardour.org/using-control-surfaces/devices-using-mackielogic-control-protocol/)
- [MongLong0214/logic-pro-mcp](https://github.com/MongLong0214/logic-pro-mcp), [koltyj/logic-pro-mcp](https://github.com/koltyj/logic-pro-mcp), [aircrack-ng-debug/Logic-Pro-MCP](https://github.com/aircrack-ng-debug/Logic-Pro-MCP), [kiki830621/che-logic-pro-mcp](https://github.com/kiki830621/che-logic-pro-mcp)
- [Understanding Mackie Control Protocol (Silhm wiki)](https://github.com/Silhm/bcf-scribble-strips/wiki/Understanding-Mackie-Control-Protocol), [Logic Control (Wikipedia)](https://en.wikipedia.org/wiki/Logic_Control)
