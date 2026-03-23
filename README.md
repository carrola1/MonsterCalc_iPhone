# MonsterCalc iPhone

MonsterCalc iPhone is a scratchpad calculator for iOS. It keeps a fast one-expression-per-line workflow with live results, variables, `ans`, and `lineX` references.

## Current Status

This repo now has:

- a working SwiftUI iPhone app target
- a custom MonsterCalc keyboard system for `Text`, `Calc`, `Math`, `Convert`, `EE`, and `Prog`
- a line-by-line evaluator with math, programming, and EE helpers
- inline ghost hints for built-in functions
- tappable live results that can insert `lineX`
- a top-right hamburger menu for demo/reset/help/settings actions
- an XCTest target for core regression coverage
- an XCUITest target with screenshot-based UI smoke tests
- baseline-backed XCUITest snapshot verification
- a Maestro smoke flow for black-box UI automation
- an HTML user guide

## Open In Xcode

Open:

- `MonsterCalc_iPhone.xcodeproj`

Then run the `MonsterCalc_iPhone` scheme on either:

- an iPhone simulator
- a connected iPhone

## Running Tests

From Xcode:

1. Open `MonsterCalc_iPhone.xcodeproj`
2. Select the `MonsterCalc_iPhone` scheme
3. Press `Cmd+U`

From Terminal with full Xcode selected:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project MonsterCalc_iPhone.xcodeproj \
  -scheme MonsterCalc_iPhone \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Notes:

- The shared scheme includes the `MonsterCalc_iPhoneTests` target.
- The shared scheme also includes `MonsterCalc_iPhoneUITests`.
- The unit tests focus on the evaluator and view-model behavior.
- The UI tests launch the app, open the custom keyboard, rotate the simulator, and attach screenshots to the test report.
- The UI tests can also verify against recorded PNG baselines in `MonsterCalc_iPhoneUITests/__Snapshots__/`.
- If a baseline PNG is missing, the UI test will auto-record it on the first passing run.
- If your local simulator name differs, update the `-destination` value.

### UI snapshot-style tests

The UI test bundle uses `XCUIScreen.main.screenshot()` and stores the images as XCTest attachments in the test report.

Current UI coverage includes:

- portrait launch baseline
- hamburger/help menu snapshot
- keyboard mode snapshots in portrait and landscape

To record or refresh the golden baselines:

```bash
MONSTERCALC_RECORD_SNAPSHOTS=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project MonsterCalc_iPhone.xcodeproj \
  -scheme MonsterCalc_iPhone \
  -destination 'platform=iOS Simulator,id=4F200DF1-0C16-4859-8B9F-DFCE571FC78A'
```

To verify against the recorded baselines:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project MonsterCalc_iPhone.xcodeproj \
  -scheme MonsterCalc_iPhone \
  -destination 'platform=iOS Simulator,id=4F200DF1-0C16-4859-8B9F-DFCE571FC78A'
```

If you just want to bootstrap the snapshot folder, a normal test run is enough. Missing PNGs are recorded automatically the first time.

To review the captured screenshots in Xcode:

1. Run `Cmd+U`
2. Open the `Report navigator`
3. Select the latest test run
4. Open the UI test activities and attachments

### Maestro smoke flow

A simple black-box UI flow lives at `.maestro/smoke.yaml`.

Run it with:

```bash
maestro test .maestro/smoke.yaml
```

If `maestro` is installed but not on your shell `PATH`, check:

```bash
which maestro
ls /opt/homebrew/bin/maestro /usr/local/bin/maestro 2>/dev/null
```

## User Guide

Open the HTML guide in a browser:

- `MonsterCalc_iPhone/UserGuide.html`

It includes:

- how the scratchpad works
- keyboard mode overview
- variables, `ans`, and `lineX`
- built-in functions, descriptions, and examples
- tips for using the iPhone UI efficiently

## Feature Coverage

### Scratchpad workflow

- one expression per line
- live result pane
- comments with `#`
- variable assignment, for example `x = 2*pi`
- previous-result reference with `ans`
- line reference with `line2`, `line7`, and so on
- token insertion help for the in-progress unit conversion keyboard
- persistent result-format and significant-figure settings

### Math

- arithmetic: `+ - * /`
- percent suffix: `%`
- exponent: `^`
- constants: `pi`, `e`
- trig: `sin`, `cos`, `tan`, `asin`, `acos`, `atan`
- logs: `log`, `log10`, `log2`, `exp`
- rounding and aggregate helpers: `floor`, `ceil`, `min`, `max`, `sum`, `mod`
- conversions: `deg`, `rad`
- probability helpers: `pdf`, `cdf`
- engineering suffixes: `p`, `n`, `u`, `m`, `k`, `M`, `G`

### Programming

- hex and binary literals: `0x10`, `0b1010`
- bitwise operators: `&`, `|`, `xor`, `<<`, `>>`
- format helpers: `hex`, `bin`
- bit helpers: `bitget`, `bitset`
- text helpers: `a2h`, `h2a`

### Electrical / EE

- `vdiv`
- `rpar`
- `findres`
- `findrdiv`
- `findv`, `findi`, `findr`
- `xc`, `xl`
- `db`, `db10`
- `fc_rc`, `tau`
- `rc_charge`, `rc_discharge`
- `ledr`
- `adc`, `dac`

### Still In Progress

- broader feature coverage outside the current math/programming/EE core

## Project Layout

- `MonsterCalc_iPhone/ContentView.swift`: main SwiftUI screen and view model
- `MonsterCalc_iPhone/ScratchpadTextView.swift`: editor bridge, custom keyboards, ghost hints, line numbers
- `MonsterCalc_iPhone/ScratchpadEngine.swift`: document evaluator and built-in functions
- `MonsterCalc_iPhone/ExpressionParser.swift`: expression tokenizer and parser
- `MonsterCalc_iPhone/DemoSheet.swift`: starter demo content
- `MonsterCalc_iPhoneTests/`: XCTest coverage
- `MonsterCalc_iPhoneUITests/`: XCUITest launch and screenshot coverage
- `MonsterCalc_iPhoneUITests/__Snapshots__/`: baseline PNGs for snapshot verification
- `.maestro/`: Maestro smoke flow and notes
- `MonsterCalc_iPhone/UserGuide.html`: end-user documentation
- `MonsterCalc_iPhone/ReleaseNotes.html`: in-app release notes

## Known Limits

- The app is still growing beyond the current math/programming/EE core.
- Some areas, like unit conversion, are still being finished.
- UI-heavy behavior is better verified in Xcode/simulator/device than from command-line-only environments.
