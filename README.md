# KeyTally

KeyTally is a local macOS 15+ menu-bar app that counts physical keyboard
presses separately for each CoreHID keyboard. It stores daily aggregate counts
only, then derives daily and lifetime totals from those records.

KeyTally never stores typed characters, key order, individual event timestamps,
application or window information, raw HID reports, analytics, telemetry, or
network data. The app does require macOS Input Monitoring permission because
CoreHID keyboard elements are protected input.

This repository contains source code and tests. It intentionally does not
publish a built application, installer, DMG, updater, or App Store package.
The V1 target is local use and transparent review.

## Launch articles

- [English launch essay](docs/KeyTally-launch-en.md)
- [中文介绍文章](docs/KeyTally-launch-zh.md)

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

The build script generates `Resources/AppIcon.icns` from `icon.png` when
needed, embeds it in the app bundle, and ad-hoc-signs the result. It contains
no Developer ID or Apple Team Identifier and is not a public-distribution
signature.

## First launch and permission

1. Open KeyTally from the menu bar.
2. Choose **Request Input Monitoring**.
3. Enable the exact current KeyTally build under **System Settings → Privacy &
   Security → Input Monitoring**.
4. Return to KeyTally. It rechecks CoreHID automatically; **Recheck Keyboard
   Access** is also available.

Ad-hoc signing is deliberate for local use. macOS associates Input Monitoring
with the signed application identity, so rebuilding or replacing `KeyTally.app`
can require authorization again. Grant access after the final build and do not
replace that bundle without rechecking the permission.

Counts are stored at:

```text
~/Library/Application Support/KeyTally/counts.json
```

The count file is local user data and is excluded from Git by `.gitignore`.

## V1 boundaries

- Standard Keyboard/Keypad HID usages only
- Built-in, USB, and CoreHID-visible Bluetooth keyboards
- No media or vendor-specific controls
- No raw HID report parsing or CGEventTap fallback
- No device merging or receiver reconstruction
- No virtual HID devices or virtual-device entitlement
- No SQLite, updater, installer, DMG, or Launch at Login

## Testing status

The unit suite covers transition filtering, simultaneous and per-device state,
pause/resume behavior, identity hashing, JSON persistence, daily/lifetime
totals, rename, reset, and aggregate CSV export. Run it with `swift test` on
macOS 15+.

CoreHID access and physical key behavior require manual hardware validation;
GitHub Actions cannot substitute for testing a built-in keyboard, USB keyboard,
or Bluetooth keyboard. External device names and stable IDs depend on metadata
provided by macOS.

After granting Input Monitoring, verify:

- A, Shift, Space, Return, arrows, and a function key count once per physical press.
- Holding a key does not add auto-repeat counts.
- Pause and resume do not count a key that stayed held.
- Built-in and external keyboards accumulate separate totals.
- USB and Bluetooth keyboards retain identity after reconnect when their HID metadata permits it.
- CSV contains aggregate rows only.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the local development boundaries.

## License

KeyTally is released under the [MIT License](LICENSE).

---

# KeyTally（中文说明）

KeyTally 是一款仅在本机运行的 macOS 15+ 菜单栏应用，使用 CoreHID 分别统计每个物理键盘的按键次数。应用只保存按天汇总的计数，并由这些记录计算每日总数和终身累计总数。

KeyTally 不保存输入字符、按键顺序、单个事件时间戳、应用或窗口信息、原始 HID 报告、分析数据、遥测数据，也不访问网络。由于 CoreHID 键盘元素属于受保护的输入数据，应用需要 macOS 的“输入监控”权限。

本仓库只包含源代码和测试，不发布编译好的应用、安装器、DMG、更新器或 App Store 软件包。V1 的目标是本地使用和透明审查。

## 本地构建

要求：

- macOS 15 或更高版本
- 安装了 macOS SDK 的 Xcode

运行：

```sh
swift test
./scripts/build-local.sh
open dist/KeyTally.app
```

构建脚本会在需要时根据 `icon.png` 生成 `Resources/AppIcon.icns`，将资源嵌入应用，并使用本地 ad-hoc 签名。应用不包含 Developer ID 或 Apple Team Identifier，也不是用于公开分发的签名。

## 首次启动与权限

1. 从菜单栏打开 KeyTally。
2. 选择 **Request Input Monitoring（请求输入监控）**。
3. 在 **系统设置 → 隐私与安全性 → 输入监控** 中启用当前这一个 KeyTally 构建版本。
4. 返回 KeyTally。应用会自动重新检查 CoreHID，也可以使用 **Recheck Keyboard Access（重新检查键盘访问）**。

ad-hoc 签名是本地使用的有意选择。macOS 会根据已签名应用的身份关联输入监控权限，因此重新构建或替换 `KeyTally.app` 后可能需要再次授权。请在最终构建后授予权限，替换应用包后重新检查权限。

计数文件保存在：

```text
~/Library/Application Support/KeyTally/counts.json
```

该文件属于本机用户数据，已由 `.gitignore` 排除，不应提交到 Git。

## V1 范围

- 仅统计标准 Keyboard/Keypad HID 用法
- 支持内置键盘、USB 键盘，以及 CoreHID 能识别的蓝牙键盘
- 不包含媒体键或厂商自定义控制
- 不解析原始 HID 报告，也不使用 CGEventTap 备用路径
- 不进行设备合并或接收器重建
- 不创建虚拟 HID 设备，也不申请虚拟设备 entitlement
- 不使用 SQLite、更新器、安装器、DMG 或登录启动

## 测试状态

单元测试覆盖按键转换过滤、同时按键、按键盘区分的状态、暂停/恢复、设备身份哈希、JSON 持久化、每日/终身总数、重命名、重置以及汇总 CSV 导出。请在 macOS 15+ 上运行 `swift test`。

CoreHID 权限和真实按键行为必须在实体硬件上手动验证；GitHub Actions 不能替代对内置键盘、USB 键盘或蓝牙键盘的测试。外接设备名称和稳定 ID 取决于 macOS 提供的设备元数据。

授予“输入监控”权限后，请验证：

- A、Shift、Space、Return、方向键和功能键，每次实体按键只计数一次。
- 长按按键不会因自动重复而增加计数。
- 暂停和恢复时，持续按住的按键不会被重复计数。
- 内置键盘和外接键盘分别累计计数。
- 当 HID 元数据允许时，USB 和蓝牙键盘重新连接后仍能保持身份。
- CSV 只包含汇总行。

本地开发边界请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

KeyTally 使用 [MIT 许可证](LICENSE) 发布。
