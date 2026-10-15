---
status: accepted
date: 2026-10-15
---

# pi reaches sharpfive through its shell tool and a skill; the product ships as a modified pi

pi could reach the limbs three ways: typed tools registered by an extension, one per verb; a few coarse typed tools with a verb argument; or its ordinary shell tool running the `sf` CLI with the skill as the schema. We chose the shell. The daemon already answers in one JSON line per call, the readback and the gate catch bad arguments, and a typed tool per verb would mean two surfaces to keep in sync for every change. pi's own docs state this idiom: CLIs compose from bash, and a skill's body is loaded only when it applies. One thin extension covers the two things the shell cannot: a `tool_call` hook that shows gates in pi's own dialog so the agent cannot talk past them, and a `before_agent_start` hook that writes the turn summary. Rejected: typed tools now (they remain a possible later layer, like MCP), and no extension at all (the agent would be the one asking the gate question in its own words).

For market, sharpfive does not ship as an extension installed into stock pi. It ships as a modified copy of pi's source with the same extension code built in. The extension is the development form of that code. Decided in [#11](https://github.com/ambiguouscherry/sharpfive/issues/11).

## Consequences

- Verbs and their arguments live in the binary (`sf help --json`) and the skill holds only rules and an index; adding a verb is a CLI change plus a paragraph, never an extension change.
- The gate dialog is built from the daemon's payload, so the daemon, not the agent, owns the wording of every gate.
- The product depends on pi's extension hooks (`tool_call`, `before_agent_start`, `sendMessage`) staying stable, or on tracking upstream in the fork.
