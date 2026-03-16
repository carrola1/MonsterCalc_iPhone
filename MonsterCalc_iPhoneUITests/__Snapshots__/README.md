This directory stores baseline PNGs for the XCUITest snapshot checks in
`MonsterCalc_iPhoneUITests.swift`.

To record or refresh baselines:

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
