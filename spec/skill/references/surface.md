# surface: the control-surface verbs

The daemon owns an emulated Mackie Control. It works blind: every fact comes from the surface's feedback, never from the screen. `sf help <verb> --json` has the arguments.

## Read

```
sf state                    # parsed model: connection, strips, assignment mode, plugin edit page, transport, directory
sf tracks                   # every track: index, name, colour, mute, solo, arm
sf plugin inventory "hello :P"      # slots by MCU index; the inspector hides empty slots, the MCU index is the key
sf param list "hello :P" 1          # the parameters of insert 1, paged, with units once learned
sf param get "hello :P" 1 Attack
```

## Write

```
sf select "Inst 2"
sf fader set "hello :P" -6dB
sf mute "hello :P" on
sf plugin insert "Inst 2" inst "ES2"          # instrument slot
sf plugin insert "hello :P" 2 "Compressor"    # insert 2; gated plugin-replace if occupied
sf param set "hello :P" 1 Attack 30ms
sf param nudge "hello :P" 1 Ratio +2          # discrete: two steps
sf learn "hello :P" 1                         # collect full names and units for a plug-in (about 1 s per parameter)
sf locate 17.3
sf transport play
sf transport record --replace                 # gated record-over
sf notes send phrase.mid                      # queues a stamped phrase; record is the gate
```

Reply for a write:

```
{"status":"confirmed","requested":{"Attack":"30 ms"},"observed":{"Attack":"30 ms"},
 "resolved":{"track":"hello :P","strip":1,"slot":1,"page":1,"cell":2},"settledAfterMs":140}
```

## Regions (the round-trip)

```
sf region export                          # snapshot of every region; returns the file path; changes nothing
sf region read "hello :P@3"               # start, end, name, loop, contents, from the accessibility element
sf region replace "hello :P@3" edited.mid # gated region-replace: snapshot, clear, place, compare, in one verb
sf region compare snapshot.mid            # export again and diff
sf region undo snapshot.mid               # Edit > Undo until the export matches
sf region rename "hello :P@3" "bass verse 1"   # only when the region still carries Logic's default name
```

A gated reply:

```
{"status":"gated","kind":"region-replace","target":"hello :P @ bar 3 to 4.3 (\"second\")",
 "diff":{"moved":2,"deleted":0,"added":1,"first":["C3 3.2 → 3.3","+ E3 4.1"]},
 "undo":"snapshot + Edit > Undo","allowance":"offered"}
```

Refused up front: looped regions, take folders, overlapping regions on the track (`reason: region-refused`).

## Allowances and consent

```
sf allow region-replace          # same as "Yes for this project" in the dialog
sf allow region-replace --revoke
sf consent list
sf consent revoke screen
```
