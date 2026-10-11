---
status: accepted
date: 2026-10-11
---

# One bridge daemon owns every endpoint Logic sees

Logic streams control-surface state continuously (LCD, LEDs, rings, meters, beats display) and shows the full parameter name only in a 2-second transient; anything not listening at that moment loses the fact. Logic also excludes the control-surface port from sequencer input, so notes need a second endpoint whose timing depends on the transport state the surface reports. We therefore run a single long-lived daemon that owns the Mackie Control pair and the notes source, accumulates state, and serves stateless CLI commands over a Unix socket; EDIT and WRITE are tool families on that one process. Rejected: one process per command (loses transients, pays a reconnect and full repaint per call) and separate EDIT and WRITE processes (race on transport state). Consequence: the daemon is the only thing that may touch CoreMIDI, and every tool reply reports observed state, never assumed state.
