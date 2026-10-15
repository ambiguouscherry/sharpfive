# audio: the tap

AUNetSend sits on Stereo Out; the daemon hosts AUNetReceive and folds the stream into 100 ms windows stamped with the beats display. 16-bit PCM as Logic sends it. No consent: the tap is inside Logic.

```
sf audio status                          # sender present, format, underflows
sf audio meters --for 4bars              # windows: position, peak dBFS, RMS dBFS, clipped; summary: max peak, clip count, loudest bar
sf audio meters --until stop             # streams until the transport stops
sf audio capture take.wav --for 8bars    # the mix to a file, for hear or for the musician
```

Stopped transport streams digital zeros; the first audio arrives 39 to 125 ms after PLAY. An `Underflow` status in the first 0.4 s after a transport start is cosmetic.

Use meters for gain staging and clipping checks, and for hearing a plug-in you built (A/B on the same bars, octave bands).
