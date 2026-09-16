# KeyTally

**English** | [中文](README.zh-CN.md)

KeyTally is a local macOS 15+ menu-bar app that counts physical input separately for each CoreHID keyboard and mouse. It stores daily aggregate counts only, then derives daily and lifetime totals from those records.

KeyTally never stores typed characters, key order, individual event timestamps, application or window information, raw HID reports, analytics, telemetry, or network data. The app does require macOS Input Monitoring permission because CoreHID keyboard and pointer elements are protected input.

This repository contains source code and tests. It intentionally does not publish a built application, installer, DMG, updater, or App Store package. The V1 target is local use and transparent review.

## Launch articles

- [English launch essay](docs/KeyTally-launch-en.md)
- [中文介绍文章](docs/KeyTally-launch-zh.md)

## Features

- Counts physical keyboard presses per device (no key auto-repeat inflation)
- Counts mouse left/right/wheel clicks; wheel **scroll** is shown in the mouse panel only and is **not** added into headline totals
- **Today** and **Lifetime** totals are split into **Keyboard** and **Mouse**
- Per-device filter, daily history, US keyboard heatmap, mouse activity panel
- Pause/resume, rename devices, reset counts, export aggregate CSV
- Menu bar status plus a dashboard window

## Build locally

Requirements:

- macOS 15 or later
- Xcode with the macOS SDK

Run:

```sh
swift test
./scripts/build-local.sh
open dist/KeyTally.app
```

The build script generates `Resources/AppIcon.icns` from `icon.png` when needed and embeds it in the app bundle. Local builds are for personal use; they are not App Store or Developer ID distribution packages.

## First launch and permission

1. Open KeyTally from the menu bar.
2. Choose **Request Input Monitoring**.
3. Enable the exact current KeyTally build under **System Settings → Privacy & Security → Input Monitoring**.
4. Return to KeyTally. It rechecks CoreHID automatically; **Recheck Keyboard Access** is also available.

macOS associates Input Monitoring with the signed application identity, so rebuilding or replacing `KeyTally.app` can require authorization again. Grant access after the final build.

Daily counts are stored under the standard macOS Application Support folder for KeyTally (`counts.json`). That file is local user data and is excluded from Git by `.gitignore`.

## V1 boundaries

- Standard Keyboard/Keypad HID usages, plus mouse buttons and wheel
- Built-in, USB, and CoreHID-visible Bluetooth keyboards and mice
- No media or vendor-specific controls
- No raw HID report parsing or CGEventTap fallback
- No device merging or receiver reconstruction
- No virtual HID devices or virtual-device entitlement
- No SQLite, updater, installer, DMG, or Launch at Login

## Testing status

The unit suite covers transition filtering, simultaneous and per-device state, pause/resume behavior, identity hashing, JSON persistence, daily/lifetime totals (keyboard vs mouse, excluding wheel scroll from headline totals), rename, reset, and aggregate CSV export. Run it with `swift test` on macOS 15+.

CoreHID access and physical key behavior require manual hardware validation; GitHub Actions cannot substitute for testing a built-in keyboard, USB keyboard, Bluetooth keyboard, or mouse. External device names and stable IDs depend on metadata provided by macOS.

After granting Input Monitoring, verify:

- A, Shift, Space, Return, arrows, and a function key count once per physical press.
- Holding a key does not add auto-repeat counts.
- Pause and resume do not count a key that stayed held.
- Built-in and external keyboards accumulate separate totals.
- Mouse clicks count; wheel scroll appears in the mouse section only.
- USB and Bluetooth devices retain identity after reconnect when their HID metadata permits it.
- CSV contains aggregate rows only.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development boundaries.

## License

KeyTally is released under the [MIT License](LICENSE).
