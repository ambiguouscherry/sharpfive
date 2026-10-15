# surface: the control-surface verbs

The daemon owns an emulated Mackie Control. It works blind: every fact comes from the surface's feedback, never from the screen. `+5 help <verb> --json` has the arguments.

## Read

```
+5 state                    # parsed model: connection, strips, assignment mode, plugin edit page, transport, directory
+5 tracks                   # every track: index, name, colour, mute, solo, arm
+5 plugin inventory "hello :P"      # slots by MCU index; the inspector hides empty slots, the MCU index is the key
+5 param list "hello :P" 1          # the parameters of insert 1, paged, with units once learned
+5 param get "hello :P" 1 Attack
```

## Write

```
+5 select "Inst 2"
+5 fader set "hello :P" -6dB
+5 mute "hello :P" on
+5 plugin insert "Inst 2" inst "ES2"          # instrument slot
+5 plugin insert "hello :P" 2 "Compressor"    # insert 2; gated plugin-replace if occupied
+5 param set "hello :P" 1 Attack 30ms
+5 param nudge "hello :P" 1 Ratio +2          # discrete: two steps
+5 learn "hello :P" 1                         # collect full names and units for a plug-in (about 1 s per parameter)
+5 locate 17.3
+5 transport play
+5 transport record --replace                 # gated record-over
+5 notes send phrase.mid                      # queues a stamped phrase; record is the gate
```

Reply for a write:

```
{"status":"confirmed","requested":{"Attack":"30 ms"},"observed":{"Attack":"30 ms"},
 "resolved":{"track":"hello :P","strip":1,"slot":1,"page":1,"cell":2},"settledAfterMs":140}
```

## Regions (the round-trip)

```
+5 region export                          # snapshot of every region; returns the file path; changes nothing
+5 region read "hello :P@3"               # start, end, name, loop, contents, from the accessibility element
+5 region replace "hello :P@3" edited.mid # gated region-replace: snapshot, clear, place, compare, in one verb
+5 region compare snapshot.mid            # export again and diff
+5 region undo snapshot.mid               # Edit > Undo until the export matches
+5 region rename "hello :P@3" "bass verse 1"   # only when the region still carries Logic's default name
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
+5 allow region-replace          # same as "Yes for this project" in the dialog
+5 allow region-replace --revoke
+5 consent list
+5 consent revoke screen
```
