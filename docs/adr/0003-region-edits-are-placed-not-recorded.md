---
status: accepted
date: 2026-10-11
---

# Region edits are placed as a file, not re-recorded

The obvious way to change notes in a Logic region, given a working MIDI write path, is to re-record the edited notes over the old ones. We don't. Recording lands every note 19–87 ms late by a varying amount (measured in #8 and #30), so each edit would drift the musician's own notes, and the REPLACE span depends on STOP timing. Instead the agent writes the edited region as a Standard MIDI File and places it: delete the old region, locate to its start bar, `File > Import > MIDI File…`. Import keeps tick positions exactly, carries every event (controllers, pitch bend, aftertouch) without the write path knowing about them, and ignores the project tempo when the file carries none. Re-recording survives only as a gated fallback for regions that are already on the grid, because the fallback quantises. Decided in [#10](https://github.com/ambiguouscherry/sharpfive/issues/10).

## Consequences

- The round-trip depends on the Accessibility API (menu presses, the panel-service process, region elements), not only on the control surface. The EDIT limb's "works blind" rule gets an exception for region edits.
- A region's identity is its track plus start bar read from the accessibility tree; the export file alone cannot identify a region.
