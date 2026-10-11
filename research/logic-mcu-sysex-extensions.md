# Logic Pro's "undocumented" MCU SysEx on connect (cmds 0A/0B/0C/0E/20/21/72)

*Research note for sharpfive. Resolves issue #23 (surfaced by the #5 handshake spike). Companion to [research/mcu-protocol.md](mcu-protocol.md).*

All byte values hex. `<Hdr>` = `F0 00 00 66 14` (Mackie manufacturer ID + device `14` = main unit; `15` = extender).

---

## TL;DR

Six of the seven commands are **not undocumented at all** — they are the "Configuration" and "Metering" messages from Appendix B of the original Emagic/Apple *Logic Control* manual, the primary byte-level spec for this protocol. Logic sends them once at connect to put a hardware surface into its default configuration. The seventh, `72`, is **Behringer's X-Touch scribble-strip colour extension**, which Logic sends under the plain Mackie header to any device registered as a Mackie Control. It carries **per-strip track colour**, quantised to 3-bit RGB.

| Cmd | Observed payload | Meaning (source) | Daemon must… | Worth exposing? |
|---|---|---|---|---|
| `0A` | `01` | Transport button click **on** (LC manual) | ignore | no |
| `0B` | `0F` | LCD backlight saver timeout = 15 min (LC manual) | ignore | no |
| `0C` | `00` | Touchless fader moves **off** — only send fader moves while touched (LC manual) | ignore (but informs write path, see §3) | no |
| `0E` | `ii 03`, ii = 0–8 | Fader touch sensitivity = 3 (default) for strips 1–8 + master (LC manual) | ignore | no |
| `20` | `ii 07`, ii = 0–7 | Channel meter mode: LCD meter + peak hold + signal LED all **enabled** per strip (LC manual) | ignore; optionally record | marginal |
| `21` | `01` | Global LCD meter mode = **vertical** (LC manual) | ignore; optionally record | marginal |
| `72` | `02 02 05 04 07 07 07 07` | X-Touch scribble-strip colours, one byte per strip 1–8 (Ardour source, X-Touch community doc) | **parse and store** | **yes — track colour** |

None of them expects a reply: the Logic Control manual marks every one `Transmitted: No`/`None`. A daemon that swallows them silently is fully protocol-correct. The only one that should be *parsed* is `72`.

---

## 1. Primary source: Logic Control manual, Appendix B

The Logic Control hardware manual (Emagic, c. 2002; Logic Control was the Mackie Control's direct ancestor and shares the byte protocol) has a "MIDI Implementation" appendix. The relevant sections, quoted from the PDF (mirror: [fullcompass.com, 4705-LogicControlManual.pdf](https://www.fullcompass.com/common/files/4705-LogicControlManual.pdf), pp. 170–171 and 178–179 in the printed numbering):

### 1.1 Configuration Messages (p. 171)

```
Received:
      <Hdr> 0A tt F7        Transport button click
      <Hdr> 0B ll F7        LCD back light saver
      <Hdr> 0C mm F7        Touchless movable faders
      <Hdr> 0E ii ss F7     Fader touch sensitivity
Transmitted:     No
tt    00 = no transport button click
      01 = transport button click (default)
ll    00 = LCD back light off
      01 to 7F = LCD back light on, with time out in minutes (default: 0F = 15 minutes)
mm    00 = fader movements are only transmitted if the fader has been recognized as touched
      01 = fader movements are also transmitted if the fader has not been recognized
           as touched (e.g. with finger nail or pen)
ii    Fader ID (00 thru 07; Master = 08)
ss    Fader touch sensitivity (00 to 05; default: 03)
```

Mapping to the spike's capture:

- `0A 01` — transport click on (the default).
- `0B 0F` — backlight saver 15 min (the default).
- `0C 00` — touchless faders off (the default).
- `0E ii 03` for ii = `00`–`08` — touch sensitivity 3 (the default) on all eight channel faders plus master. This is why the spike saw strips **0–8** for `0E` but only 0–7 for `20`: `0E` addresses faders (master included), `20` addresses channel meters (no master meter on the LC/MCU).

So on connect Logic simply pushes the factory defaults for every configurable hardware setting. Nothing here is per-track or per-session state.

### 1.2 Metering (pp. 178–179)

```
Received:
      D0, XX                       Peak level
      <Hdr>, 20, ii, mm, F7        Channel meter mode
      <Hdr>, 21, yy, F7            Global LCD meter mode
Transmitted:     None
ii    Channel ID (0 to 7)
mm    mode bit map in the form of ( 0 0 0 0 0 l p s ):
      l      Enable level meter on LCD
      p      Enable peak hold display (horizontal only)
      s      Enable Signal LED
yy    00 = horizontal; 01 = vertical
```

Plus the note: *"While the LCD switches between horizontal and vertical metering mode, it ignores LCD messages. After you sent an LCD metering mode change message, you should delay LCD messages for at least 600 ms."*

Mapping to the capture:

- `20 ii 07` for ii = `00`–`07` — all three bits set: LCD level meter on, peak hold on, signal LED on, for every strip.
- `21 01` — vertical LCD metering (the meter bar overlays the last character of each 7-char cell, per the manual's LCD chapter and Apple's current guide).

Ardour's host-side implementation matches exactly: [`meter.cc`](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc) sends `<Hdr> 20 <id> 07|00 F7` with the comment *"Enable (0x07) / Disable (0x00) level meter on LCD, peak hold display on horizontal meter and signal LED"*. The TouchMCU protocol doc ([NicoG60/TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)), which is derived from this appendix, lists the same seven commands with the same semantics and marks `0A`, `0B`, `0C`, `0E`, `21` as verified against real MCU hardware.

### 1.3 How these map to Logic's UI

Logic exposes the meter mode on the surface itself: Shift + NAME/VALUE *"cycle[s] through three level meter modes on the main LCD"* — Vertical, Horizontal with Peak Hold, Off ([Apple, Mackie Control display control buttons](https://support.apple.com/guide/logicpro-css/ctls72224fdb/mac)). Each cycle step should produce a fresh `21` (and possibly `20`) message. The spike observed the default (vertical, all enabled). Transport click, backlight timeout and touch sensitivity have no Logic-side UI that I could find in the current Control Surfaces Support guide; Logic appears to just send the hardware defaults.

---

## 2. Cmd `72`: X-Touch scribble-strip colours (= track colour)

### 2.1 What it is

`72` is **not** in the Logic Control manual (its undocumented ranges are `05–09`, `0D`, `15–17`, `19–1F`, `22–60`, `64–7F`). It is Behringer's extension for the X-Touch, whose scribble strips have RGB backlights. The message is:

```
F0 00 00 66 14 72 c1 c2 c3 c4 c5 c6 c7 c8 F7      (main unit, strips 1–8)
F0 00 00 66 15 72 c1 ... c8 F7                    (extender)
```

with one colour byte per strip, left to right:

| Byte | Colour | Bits (b2 b1 b0 = B G R) |
|---|---|---|
| `00` | off / black | 000 |
| `01` | red | 001 |
| `02` | green | 010 |
| `03` | yellow | 011 |
| `04` | blue | 100 |
| `05` | magenta / purple | 101 |
| `06` | cyan | 110 |
| `07` | white | 111 |

Sources:

- **Ardour source** — the authoritative open implementation. [`surface.cc`](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.cc) `Surface::display_colors_on_xtouch()` emits `sysex_hdr() << 0x72 << 8 colour bytes << eox` — i.e. the ordinary Mackie header, not an Xctl header. The enum in [`surface.h`](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.h) is `enum XTouchColors { Off, Red, Green, Yellow, Blue, Purple, Cyan, White }`. `convert_color_to_xtouch_value()` normalises the track's RGB so the brightest channel is 255, then sets bit 0 if R > 7F, bit 1 if G > 7F, bit 2 if B > 7F — and returns `White` for black, *"because black means off"*. Added in Ardour commit [777c7c6](https://github.com/Ardour/ardour/commit/777c7c6c037d604f1456889d7435fa90aa5e8109) ("added trackcolors to X-Touch"); Ardour gates it behind an `<IsXTouch>` device flag because it only *does* anything on X-Touch hardware.
- **X-Touch community documentation** — [Ardour forum, "X-Touch scribble strips?"](https://discourse.ardour.org/t/x-touch-scribble-strips/100627): `F0 00 00 66 14 72` + eight colour bytes + `F7`, codes `00` blank, `01` red, `02` green, `03` yellow, `04` blue, `05` purple, `06` cyan, `07` white; *"works in standard Mackie Control mode over USB or network, without XCtl software"*; credited to OSIMidi. Behringer later documented the string in the X-Touch Extender manual (reported as p. 25 by a forum poster; Behringer's own MIDI-implementation PDF on the Music Tribe CDN returned HTTP 500 during this research, so I could not quote it directly — treat the byte table above as confirmed by two independent working implementations rather than by the vendor).
- **Inversion bits** — one forum report says the Extender manual also defines bits 4–5 of the colour byte as "invert" flags for the upper/lower half of the display (so `18`–`1F` would be inverted colours). Unverified; Logic sent only `00`–`07` in the capture. **Guess, not fact.**

### 2.2 What Logic is doing with it

The spike's virtual port was registered as a plain **Mackie Control**, not an X-Touch, and still received `72`. So Logic (at least 11.2) sends X-Touch colour SysEx unconditionally to every Mackie Control device — reasonable from Apple's side, since the X-Touch and its clones (iCON, etc.) all register as "Mackie Control" in Logic and real Mackie hardware ignores unknown commands.

Decoding the observed payload `02 02 05 04 07 07 07 07`: strips 1–2 **green**, strip 3 **magenta**, strip 4 **blue**, strips 5–8 **white**. That is a per-strip track-colour readout of the visible bank, quantised to the eight X-Touch colours. Compare against the open project when re-running the spike; expected: the first two tracks share a greenish colour, track 3 is pink/purple, track 4 blue.

Open questions to settle empirically (one spike run each; **all guesses until tested**):

1. **What does `07` (white) mean for strips 5–8?** Either (a) those strips had no track (empty bank slots — plausible if the project had four tracks), (b) the tracks had a colour Logic maps to white (greys, pale tones, or Logic's default), or (c) Logic, like Ardour, maps "no colour / black" to white. Load a 9+ track project with distinct saturated colours and compare.
2. **Does Logic resend `72` on bank/track-colour change?** Ardour only sends it from `map_stripables()` (i.e. on bank/remap), not on colour edits. Logic's behaviour is unknown. If it resends on every bank change, the daemon can keep colours in sync for free; if not, colours may go stale until the next bank step.
3. **Quantisation**: is Logic's RGB→3-bit mapping the same "brightest channel > 50 %" rule Ardour uses, or a nearest-of-eight distance? Only matters if the agent wants to round-trip colours.
4. **Firmware note**: the forum reports X-Touch firmware ≥ 1.22 may be needed for colours in MC mode. Irrelevant for the daemon (we are the device), noted for completeness.

Two sanity checks on the hypothesis: (i) Logic's release notes mention X-Touch explicitly ("Logic faders linked to a Behrigner X-Touch in control mode no longer send random MIDI messages", Logic Pro 12.0 — [Apple release notes](https://support.apple.com/en-us/109503)), so Apple treats the X-Touch as a first-class Mackie Control variant; (ii) a 2017 zZounds review of the X-Touch under Logic complained that the scribble strips were "simply a white background", consistent with colour support arriving in a later Logic version — I found no release note pinning the version. **Which Logic version introduced `72` is unknown.**

---

## 3. What the daemon must do

1. **Parse `72`, store eight colour nibbles per device ID (`14` main, `15` extender), expose them per strip.** Decode with the table in §2.1. Attach the colour to the same strip record that already carries LCD name, fader position, LED states and meter level, so `sf strips` (or whatever the readback CLI becomes) can print `name / colour / level / mute…` in one row. Only strips 1–8 of the main unit are covered; the master has no colour byte.
2. **Swallow `0A`, `0B`, `0C`, `0E` silently.** No reply is defined; they describe hardware behaviour we don't have. Optionally log them once at debug level so a future Logic version changing the defaults is noticed.
3. **Record `20`/`21` as "meter display mode" state, but don't act on it.** The daemon's meter readout comes from `D0` channel pressure regardless of what the LCD would be showing. `21` changes (via Shift+NAME/VALUE) are the only runtime signal here; they matter only if the agent ever renders a facsimile of the LCD. Note the manual's 600 ms "ignore LCD writes after a mode change" rule applies to hardware, not to us — but it does mean Logic may *pause its own LCD writes* ~600 ms after sending `21`, which is worth knowing when timing readback.
4. **`0C 00` has one write-path consequence**: Logic has told the surface it expects fader moves *only while touched*. Logic itself doesn't enforce this on input (bare pitch-bend works, per [research/mcu-protocol.md §2.1](mcu-protocol.md)), but it is further evidence that bracketing programmatic fader moves with touch notes `68+n` is the behaviour Logic is designed around.
5. **No handshake coupling.** All seven arrive after Logic has installed the surface; none is part of the `00/01/02/03` challenge and none gates further traffic. A daemon that implements nothing in this note still gets LCD, faders, LEDs and meters.

### What the stateless CLI should expose

- **Track colour** (from `72`): yes, as a named colour plus the raw 0–7 code. It is the only new per-track fact in this family and it is genuinely useful to the agent (e.g. "the drum tracks are the green ones"; colour-grouped selection; sanity-checking that a bank step landed on the expected tracks when names are truncated to 6 chars).
- **Strip type / meter mode / display mode**: `20`/`21` carry *meter display configuration*, not strip type. There is no strip-type information anywhere in this family; strip type still has to be inferred from the Global View group buttons (`3E`–`45`) or the LCD. Exposing "LCD meter mode = vertical" is harmless but low value.

---

## 4. Confidence

- `0A`/`0B`/`0C`/`0E`/`20`/`21` semantics: **high** — direct quotes from the primary spec, corroborated by Ardour's host implementation and TouchMCU's hardware tests; the observed payloads are exactly the documented defaults.
- `72` = X-Touch per-strip colour, byte table: **high** — two independent working implementations (Ardour source, community-tested message) agree on command byte, header, payload length and colour codes; the observed payload is well-formed under that reading.
- `72` payload = *Logic track colours of the visible bank*: **medium-high** — strongly implied by the data shape and by Logic sending it at all, but not yet confirmed against the project's actual track colours. One spike run closes this.
- White-for-empty-strip, resend-on-bank-change, Logic's quantisation rule, inversion bits: **guesses** — listed as experiments in §2.2.

---

## Sources

- Emagic/Apple, *Logic Control User Manual*, Appendix B "MIDI Implementation" — mirror: [fullcompass.com/common/files/4705-LogicControlManual.pdf](https://www.fullcompass.com/common/files/4705-LogicControlManual.pdf) (Configuration Messages p. 171; Metering pp. 178–179; LCD meter modes in the LCD chapter). The same appendix shipped as Appendix B of Apple's *Logic Pro 7.2.1 Dedicated Control Surface Support* manual.
- Ardour, `libs/surfaces/mackie/`: [`surface.cc`](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.cc) (`display_colors_on_xtouch`, `convert_color_to_xtouch_value`, `set_touch_sensitivity`, `toggle_backlight`), [`surface.h`](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.h) (`enum XTouchColors`), [`meter.cc`](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc) (`0x20` channel meter enable), commit [777c7c6](https://github.com/Ardour/ardour/commit/777c7c6c037d604f1456889d7435fa90aa5e8109).
- [NicoG60/TouchMCU, `doc/mackie_control_protocol.md`](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md) — reverse-engineered MCU spec with per-command hardware test status.
- [Ardour forum: "X-Touch scribble strips?"](https://discourse.ardour.org/t/x-touch-scribble-strips/100627) — community-verified `72` colour message in MC mode (OSIMidi finding, 2022); [Ableton forum: "Remote Script for Behringer X-Touch"](https://forum.ableton.com/viewtopic.php?p=1832278) — eight-colour palette, no dimming, inversion only in Xctl mode.
- Apple, *Logic Pro Control Surfaces Support*: [Mackie Control display control buttons](https://support.apple.com/guide/logicpro-css/ctls72224fdb/mac) (Shift+NAME/VALUE meter modes), [Displays overview](https://support.apple.com/guide/logicpro-css/ctls72226f72/mac); [Logic Pro release notes](https://support.apple.com/en-us/109503) (X-Touch mentions).
- Behringer, *X-Touch / X-Touch Extender MIDI Mode Implementation* (Music Tribe CDN) — **not retrieved** (HTTP 500 at research time); cited second-hand via the forum threads above.
- Raw bytes: sharpfive `prototype/mcu-spike.swift` capture against Logic Pro 11.2 (issue #23 body).
