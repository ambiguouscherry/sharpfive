# Research: AUNetSend stream format and receiver options

Resolves issue #4. Researched 2026-08-21 against Apple SDK headers, Apple developer docs, and working open-source receivers. Verified on this machine (macOS 15.7.7): `auval -a` lists both `aufx nsnd appl - Apple: AUNetSend` and `augn nrcv appl - Apple: AUNetReceive`, so the pair still ships on current macOS.

## TL;DR / Recommendation

**AUNetSend is not a dead end.** A headless, non-AU CLI process can receive its stream by *hosting* Apple's own AUNetReceive Audio Unit (hosting an AU is ordinary client code — AudioComponent/AVAudioEngine APIs — not custom-AU development, which stays out of scope). Insert AUNetSend on Logic's output bus, run a CLI receiver on localhost, done.

**Fallback (also viable, arguably cleaner):** a Core Audio **process tap** (`AudioHardwareCreateProcessTap`, macOS 14.4+) captures Logic's output directly from a CLI process with no plugin insert in the Logic project at all — at the cost of a one-time TCC audio-capture permission prompt. BlackHole is the last-resort fallback for older macOS.

## 1. How AUNetSend transmits

- **Discovery:** AUNetSend publishes a **Bonjour** service of type `_apple-ausend._tcp` (name settable via `kAUNetSendProperty_ServiceName`). Receivers resolve that to host+port. Programmatic clients must do the Bonjour resolution themselves — the SDK header states the AUNetReceive *UI view* does name resolution, not the AU ([AudioUnitProperties.h](file:///Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/AudioToolbox.framework/Headers/AudioUnitProperties.h), `kAUNetReceiveProperty_Hostname` discussion; [w7ay NetReceive notes](http://www.w7ay.net/site/Software/NetAudio/NetReceive/index.html)).
- **Transport:** TCP; default port **52800** (`kAUNetSendProperty_PortNum` is read/write). Optional password auth (`kAUNetSendProperty_Password` / `kAUNetReceiveProperty_Password`).
- **The wire protocol itself is undocumented** by Apple — only the AU property/parameter surface is public. It is, however, simple enough that third parties have spoken it raw: [PyAUNetReceive](https://github.com/rreusser/PyAUNetReceive) is a plain Python TCP client that receives AUNetSend audio headlessly (16-bit PCM, interleaved stereo, localhost:52800). So a raw-socket receiver is *possible* but format-fragile; hosting AUNetReceive avoids protocol reverse-engineering entirely.

## 2. Transmission formats

From the `NetSendPresetFormat` enum in `AudioUnitProperties.h` (macOS 15 SDK), settable via `kAUNetSendProperty_TransmissionFormatIndex` (or an arbitrary ASBD via `kAUNetSendProperty_TransmissionFormat`):

| Preset | Bitrate (per channel @ 44.1 kHz) |
|---|---|
| PCMFloat32 | 1411 kbps |
| PCMInt24 / PCMInt16 | 1058 / 706 kbps |
| Lossless24 / Lossless16 (ALAC) | ~650 / ~350 kbps |
| µLaw / IMA4 | 353 / 176 kbps |
| AAC 128/96/80/64/48/40/32 kbps pc | as named |
| AAC-LD 64/48/40/32 kbps pc | low-delay AAC |

18 presets total. For a localhost tap, **PCMFloat32** is the obvious choice: bit-identical to Logic's engine output, no codec latency, and bandwidth is irrelevant on loopback.

## 3. Can a headless non-AU process receive it?

**Yes — two proven routes:**

1. **Host AUNetReceive in a CLI process** (recommended). AUNetReceive (`augn nrcv appl`) is a *generator* AU: instantiate it with the AudioComponent API or `AVAudioEngine`, set `kAUNetReceiveProperty_Hostname` to `127.0.0.1:52800` (resolving Bonjour yourself or just hard-coding localhost), and pull rendered buffers. The [w7ay NetReceive class](http://www.w7ay.net/site/Software/NetAudio/NetReceive/index.html) is prior art: a plain Cocoa (non-AU) program hosting AUNetReceive, pulling stereo float buffers. No app bundle, no UI, no special entitlements or TCC prompts required.
2. **Speak the TCP protocol directly** ([PyAUNetReceive](https://github.com/rreusser/PyAUNetReceive)) — works but undocumented/fragile; only worth it if AU hosting is unavailable (e.g. non-Apple receiver platform).

## 4. Latency and constraints

- Uncompressed PCM over localhost adds only network-buffer latency (small, but not sample-locked to Logic's transport — the stream free-runs; there is no timestamp/transport sync in the public surface).
- Compressed presets add codec delay; AAC-LD presets exist specifically to reduce it. Irrelevant for localhost use — pick PCM.
- Connection status is observable via the `kAUNetReceiveParam_Status` parameter; disconnect/reconnect via `kAUNetSendProperty_Disconnect`.
- Constraint to note: AUNetSend must be **manually inserted and kept** on the Logic channel/output you want to tap, and Logic must be playing/rendering for data to flow. Sample rate follows the Logic project.

## 5. Fallbacks if the plugin-insert workflow is undesirable

1. **Core Audio process taps (macOS 14.4+, best modern fallback).** `CATapDescription` + `AudioHardwareCreateProcessTap` + aggregate device lets a CLI process capture the audio of a *specific process* (translate Logic's PID via `kAudioHardwarePropertyTranslatePIDToProcessObject`) or the whole system. Working sample: [insidegui/AudioCap](https://github.com/insidegui/AudioCap); deep-dive: [recall.ai on Core Audio taps](https://www.recall.ai/blog/core-audio-taps). Needs `NSAudioCaptureUsageDescription` and a one-time TCC prompt. No change to the Logic project at all. (ScreenCaptureKit can also capture app audio but is screen-recording-permission territory and heavier; process taps are the purpose-built API.)
2. **BlackHole** ([ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole), GPL-3) — virtual loopback driver; set it as Logic's output device (or half of a multi-output device to keep monitoring) and record it from any CLI audio app. Works on any macOS, but commandeers the output-device selection and needs driver installation.
3. Custom tap AU — **out of scope**, and unnecessary given the above.

## Verdict

Use **AUNetSend (PCMFloat32, localhost:52800) → headless CLI host of AUNetReceive**. Zero drivers, zero permissions, Apple-maintained codec path, and the receiver is ~100 lines of AU-hosting code. Keep **Core Audio process taps** as the documented plan B if inserting a plugin in the Logic project proves awkward.

## Sources

- macOS 15 SDK header: `AudioToolbox/AudioUnitProperties.h` (AUNetSend/AUNetReceive property enums, `NetSendPresetFormat`) — primary
- Local verification: `auval -a` on macOS 15.7.7 — primary
- [Apple: AUNetSend Properties](https://developer.apple.com/documentation/audiotoolbox/1534207-aunetsend-properties), [AUNetReceive Properties](https://developer.apple.com/documentation/audiotoolbox/1534109-aunetreceive_properties)
- [rreusser/PyAUNetReceive](https://github.com/rreusser/PyAUNetReceive) — raw-TCP headless receiver, proof of feasibility
- [w7ay NetReceive](http://www.w7ay.net/site/Software/NetAudio/NetReceive/index.html) — non-AU Cocoa host of AUNetReceive; Bonjour `_apple-ausend._tcp` details
- [insidegui/AudioCap](https://github.com/insidegui/AudioCap) — macOS 14.4+ process-tap sample; [recall.ai Core Audio taps](https://www.recall.ai/blog/core-audio-taps)
