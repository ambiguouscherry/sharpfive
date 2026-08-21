# sharpfive

A music agent for Logic Pro, built by modding the [pi](https://pi.dev) coding-agent harness. The agent handles the boring procedural producer work — plugin/parameter control, project setup — hears and inspects the session, and can sketch musical ideas for the musician to refine. It never replaces the musician.

Logic Pro has no public scripting API, so the architecture is **pi brain on the Mac + thin bridges into Logic**: CoreMIDI/IAC for notes, Mackie Control emulation for parameters and mix, accessibility/key-command scripting for structure, audio taps for listening. Each bridge is a CLI tool packaged as a pi skill.

## Status

Wayfinding. The route from concept to build-ready plan is being charted as a [wayfinder map](../../issues) — see the issue labelled `wayfinder:map`. Starting hypothesis: [logic-agent-harness-handoff.md](./logic-agent-harness-handoff.md).
