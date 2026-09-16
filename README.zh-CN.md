# KeyTally

[English](README.md) | **中文**

KeyTally 是一款仅在本机运行的 macOS 15+ 菜单栏应用，使用 CoreHID 分别统计每个物理键盘与鼠标的输入次数。应用只保存按天汇总的计数，并由这些记录计算每日总数和终身累计总数。

KeyTally 不保存输入字符、按键顺序、单个事件时间戳、应用或窗口信息、原始 HID 报告、分析数据、遥测数据，也不访问网络。由于 CoreHID 键盘与指针元素属于受保护的输入数据，应用需要 macOS 的「输入监控」权限。

本仓库只包含源代码和测试，不发布编译好的应用、安装器、DMG、更新器或 App Store 软件包。V1 的目标是本地使用和透明审查。

## 介绍文章

- [English launch essay](docs/KeyTally-launch-en.md)
- [中文介绍文章](docs/KeyTally-launch-zh.md)

## 功能

- 按设备统计实体键盘按键（长按自动重复不会抬高计数）
- 统计鼠标左键/右键/滚轮点击；滚轮**滚动**只出现在鼠标面板，**不**计入总览数字
- **今日**与**终身**总数拆分为 **Keyboard** 与 **Mouse**
- 设备筛选、每日历史、美式键盘热力图、鼠标活动面板
- 暂停/继续、设备重命名、重置计数、导出汇总 CSV
- 菜单栏状态与仪表盘窗口

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

构建脚本会在需要时根据 `icon.png` 生成 `Resources/AppIcon.icns` 并嵌入应用包。本地构建仅用于个人使用，不是 App Store 或 Developer ID 分发包。

## 首次启动与权限

1. 从菜单栏打开 KeyTally。
2. 选择 **Request Input Monitoring（请求输入监控）**。
3. 在 **系统设置 → 隐私与安全性 → 输入监控** 中启用当前这一个 KeyTally 构建版本。
4. 返回 KeyTally。应用会自动重新检查 CoreHID，也可以使用 **Recheck Keyboard Access（重新检查键盘访问）**。

macOS 会根据已签名应用的身份关联输入监控权限，因此重新构建或替换 `KeyTally.app` 后可能需要再次授权。请在最终构建后授予权限。

每日计数保存在 KeyTally 标准的 macOS Application Support 目录下的 `counts.json`。该文件属于本机用户数据，已由 `.gitignore` 排除，不应提交到 Git。

## V1 范围

- 标准 Keyboard/Keypad HID 用法，以及鼠标按键与滚轮
- 支持内置键盘、USB 键盘/鼠标，以及 CoreHID 能识别的蓝牙键盘/鼠标
- 不包含媒体键或厂商自定义控制
- 不解析原始 HID 报告，也不使用 CGEventTap 备用路径
- 不进行设备合并或接收器重建
- 不创建虚拟 HID 设备，也不申请虚拟设备 entitlement
- 不使用 SQLite、更新器、安装器、DMG 或登录启动

## 测试状态

单元测试覆盖按键转换过滤、同时按键、按设备区分的状态、暂停/恢复、设备身份哈希、JSON 持久化、每日/终身总数（键盘与鼠标分离，总览不含滚轮滚动）、重命名、重置以及汇总 CSV 导出。请在 macOS 15+ 上运行 `swift test`。

CoreHID 权限和真实输入行为必须在实体硬件上手动验证；GitHub Actions 不能替代对内置键盘、USB 键盘、蓝牙键盘或鼠标的测试。外接设备名称和稳定 ID 取决于 macOS 提供的设备元数据。

授予「输入监控」权限后，请验证：

- A、Shift、Space、Return、方向键和功能键，每次实体按键只计数一次。
- 长按按键不会因自动重复而增加计数。
- 暂停和恢复时，持续按住的按键不会被重复计数。
- 内置键盘和外接键盘分别累计计数。
- 鼠标点击会计数；滚轮滚动只出现在鼠标区域。
- 当 HID 元数据允许时，USB 和蓝牙设备重新连接后仍能保持身份。
- CSV 只包含汇总行。

开发边界请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

KeyTally 使用 [MIT 许可证](LICENSE) 发布。
