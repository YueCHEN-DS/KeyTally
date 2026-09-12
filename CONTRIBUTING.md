# Contributing to KeyTally

KeyTally is intentionally small and local-only. Contributions should preserve
the V1 boundaries:

- Count physical keyboard/keypad HID usages through CoreHID.
- Store daily aggregate counts only; never store typed characters, event order,
  timestamps, applications, windows, raw reports, or network data.
- Do not add `CGEventTap`, virtual HID devices, the virtual-device entitlement,
  media/vendor controls, device merging, telemetry, or networking without a
  separately agreed design.

## Local development

Requirements: macOS 15 or later and Xcode with the macOS SDK.

```sh
swift test
./scripts/build-local.sh
open dist/KeyTally.app
```

The unit tests use ordinary Swift values and do not create virtual HID devices.
CoreHID permission and physical keyboard behavior must be validated manually on
macOS. Because local builds are ad-hoc signed, macOS may require Input
Monitoring authorization again whenever the application bundle is rebuilt.

