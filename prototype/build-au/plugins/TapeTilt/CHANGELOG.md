# Changelog

## [1.1.0] - 2026-10-11

### Changed
- Saturation makeup now compensates the full Drive (was half): the audio tap measured the wet path +2.7 dB over
  bypass at the default Drive of 6 dB (sharpfive #16). Expect ~unity at defaults now.
- Added a 5 Hz first-order high-pass after the tilt shelves: the asymmetric tanh curve added ~6 dB of DC over the
  dry signal in the same measurement.

## [1.0.0] - 2026-10-11

### Added
- Initial build from the brief "tape saturation with a tilt EQ": Drive, Tilt, Tilt Freq, Output, Mix. Headless (no editor).
