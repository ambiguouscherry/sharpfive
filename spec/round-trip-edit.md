# Round-trip note edit: design

Resolves [Grilling: design the round-trip note-edit flow](https://github.com/ambiguouscherry/sharpfive/issues/10), 2026-10-11. Input for the tool-schemas grilling (#11). Builds on region readback (#30), MIDI write (#8), locate (#26), UI scripting (#9) and the EDIT limb contract (`spec/edit-limb.md`). Vocabulary per [CONTEXT.md](../CONTEXT.md). See [ADR 0003](../docs/adr/0003-region-edits-are-placed-not-recorded.md).

## 1. The flow

| Step | Action | Mechanism | Readback |
|---|---|---|---|
| 1 read | Export snapshot of the whole project; read the target region's element | AX press `File > Export > All MIDI Tracks as MIDI File…`, drive the panel-service process; AX read of the region `AXLayoutItem` | SMF parse; element gives name, start, end, loop handle, contents note |
| 2 plan | Build the edited note list outside Logic; produce a word diff | pure code | the diff is what the gate shows and what step 5 verifies |
| 3 gate | Ask the musician; `--confirm` re-call | pi, per the EDIT contract | |
| 4 clear | Select the old region, delete it | AX `AXSelected` write on the element (or arrow-step with `AXSelectedChildren` readback), then Delete | lane's `AXSelectedChildren` before; element gone after |
| 5 place | Locate to the region's start bar; import the edited SMF | MCU jog locate (or `Go to Position`, `/`); AX press `File > Import > MIDI File…`; panel service; tempo prompt once with "do not show again" | new element's start and end; export again and **compare** |
| 6 name | Give a default-named region a name | Region inspector `Region:` text field (`AXValue` + `AXConfirm`) or ⇧N | element description |
| 7 undo | On `failed`, or on request | AX press `Edit > Undo` up to twice (delete + import), export, compare with the before-snapshot; restore by placing the snapshot's region if that fails | compare |

Reply shape follows the EDIT contract: `{status: confirmed | uncertain | failed, requested, observed}` where `observed` is the compare result and the region element's start/end.

## 2. Decisions

- **Place, never re-record, for edits.** ADR 0003. Record stays the WRITE verb for new material. Fallback to record is allowed only when every existing note in the region is already within tolerance of the grid, because the fallback quantises the whole region; the gate says so explicitly. Margot's order for the fallback: record → quantise → humanize if requested.
- **Region handle = track + start bar**, read from the AX tree. Names are labels: the agent never identifies a region by name (four regions named "second" exist on the prototype project today).
- **Naming for tidiness.** The agent names regions that still carry Logic's default name when it touches them (e.g. the part's role: "bass verse 1"). It never overwrites a name the musician gave.
- **Timing.** The agent's new notes land on the grid. Notes the musician played never move unless the edit names them. Humanize and quantise are explicit operations.
- **Events.** The file carries every event; the first version edits notes (add, delete, move, transpose, length, velocity, quantise, humanize) and passes controller, pitch-bend, aftertouch and program-change events through untouched. Editing those lanes is a follow-up (map fog).
- **Readback = compare + element.** Export-and-compare after every edit; element read before (refuse looped regions and take folders) and after (start, end). Muted regions: the element must be checked by prototype.
- **Gate shows a word diff**: region handle and name, counts of notes moved / deleted / added with the first few named, "everything else stays". The audible A/B preview is a follow-up: duplicate the track, mute the original, place the B version on the duplicate, so the musician hears the whole mix with either version.
- **Undo** is Logic's own Undo pressed by the agent and verified by export; the snapshot is the fallback restore. ⌘Z by the musician always works and the agent's snapshot still proves the result.
- **Panels.** The export save panel and the import open panel both live in the "Open and Save Panel Service (Logic Pro)" process. Retrying `AXPress` on Save (3×, ~0.5 s apart, then `uncertain` and ask) is a stopgap; the place prototype must find a reliable press (lead: a Return keypress posted to the panel's pid).
- **Edits are gated** (destructive EDIT per the glossary). Export, element reads and the diff are not.

## 3. Silent-corruption points, and what guards each

| Point | Guard |
|---|---|
| Recording latency moves notes | no recording on the edit path; fallback only on on-grid regions, and it says it quantises |
| Tempo map changed by import | the agent's SMF carries no tempo or time-signature events; tempo prompt answered "no" once with "do not show again" |
| Wrong region replaced (same name) | handle is track + start bar; element read before delete; `AXSelectedChildren` must hold exactly one region |
| Region end wrong after place | element read of start/end compared with the plan; end-of-track meta in the SMF set to the intended end (rule to be confirmed by prototype) |
| Non-note events lost | file carries them; the agent re-emits every event it did not edit, byte for byte |
| Looped region or take folder | element read before the edit; refuse with a reason |
| Overlapping regions on the track | export shows two regions covering the same ticks; refuse |
| Save/Open press flaked | `uncertain` status, never assumed; the export reads nothing into the project, so a flaked export costs time only |
| Musician edits during the round-trip | compare fails; the agent reports and offers undo |

## 4. Facts the prototypes must settle

Place ([#32](https://github.com/ambiguouscherry/sharpfive/issues/32)): selected track vs new track on import; the region-end rule; exact tick survival and PPQ handling; region name from the track-name meta; the tempo prompt's exact text; whether import is one undo step; a reliable Save/Open press.

Select/read/rename ([#33](https://github.com/ambiguouscherry/sharpfive/issues/33)): whether writing `AXSelected` works or arrow-stepping is needed; whether the inspector name field takes an `AXValue` write; what the element says for a muted region and a take folder; the default of "Select regions on track selection".

## 5. Facts this design rests on

Logic Pro 11.2, macOS 26.7, 2026-10-11. Region readback spike (branch `prototype/region-readback`), read-only AX dumps of the Tracks area and inspector taken 2026-10-11 (regions are `AXLayoutItem` with role description "Region", settable `AXSelected`, `AXHelp` = "Region starts at 3 bars and ends at 4 bars 3 beats, MIDI region. Contains MIDI note and controller events…"; inspector `Region:` field is a settable `AXTextField` with `AXConfirm`), Apple's Logic Pro 11.2 guide on Standard MIDI files (import "placed at the playhead position, rounded to bars"; global data ignored).
