# ui: the accessibility verbs

Reads Logic's accessibility tree and presses menu items by title. Needs `screen` consent once. Track focus moves only by arrow keys or MCU SELECT; an AX write to focus succeeds and changes nothing, so `ui focus` walks and verifies.

```
sf ui tracks                              # Tracks header: index, name, focus, mute, solo, arm
sf ui track create software-instrument --name "bass"   # about 250 ms; focus lands on the new track
sf ui track delete "bass"                 # gated track-delete; refuses unless the readback shows "bass" focused
sf ui focus "hello :P"
sf ui regions "hello :P"                  # elements: start, end, name, loop handle, contents note, selected, muted
sf ui menu "File > Export > All MIDI Tracks as MIDI File…"
sf ui alert Delete                        # presses a button on the focused sheet or alert by title
sf ui panel save ~/snap.mid               # the panel lives in a separate process; uncertain if the press did not take
sf ui dump                                # the AX tree, for debugging only
```

Track types for `create`: `audio`, `software-instrument`, `external-midi` (menu press, no sheet), `drummer`, `bass-player`, `keyboard-player`, `pattern`, `guitar-or-bass` (New Tracks sheet, about 1.4 s).

Alerts: a track with regions raises "Delete Track and Regions?" as an alert window, not a sheet. `ui track delete` handles it; you do not.
