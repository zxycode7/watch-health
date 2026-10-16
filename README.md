# 健康桥 WatchBridge

开发仓库：[zxycode7/watch-health](https://github.com/zxycode7/watch-health)。协作约定见 [AGENTS.md](AGENTS.md)。

**自己的 iPhone App → 自己的 Mac → 本地只读 MCP。** 无第三方导出 App、云服务、API 密钥或运行时第三方依赖。Swift 使用 Apple SDK；Mac 使用 Python 标准库。

Apple Watch 的记录先通过 Apple 系统同步到 iPhone，再由健康桥读取。第一版不需要额外安装手表 App。

## 目前能做什么

- 选择同步步数、心率、静息心率、HRV、睡眠、体能训练、活动能量、锻炼时间、血氧、呼吸频率、体重、睡眠手腕温度。
- 本地一次性配对、HTTPS 固定证书校验、Keychain 凭据。
- HealthKit 增量与删除同步；确认成功后才保存进度；UUID 去重。
- 默认读取最近 30 天，可补录 90 天、一年、全部历史。
- MCP 查询数据清单、某天记录、指定时间段记录，保留来源、单位和原始样本。

空数据不代表 0，也不证明用户拒绝了哪项健康读取权限。第一版不跨来源直接计算步数或睡眠总量。

## Mac 安装

需要 Python 3.11+，本机 Codex CLI。无需 pip 或 npm 安装。

在本项目目录执行：

```sh
python3 scripts/install_mac.py
```

安装器会将运行文件复制到 `~/Library/Application Support/WatchBridge/runtime/`，建立私有数据库与 TLS 证书，添加本人登录后启动的 LaunchAgent，并注册 `watchbridge` MCP。现有 Codex 配置先备份，只新增这一项。若检测到同名配置或运行目录，会停止覆盖。

数据和私钥位于 `~/Library/Application Support/WatchBridge/`，不会放进项目发布目录。`service.log` 只记录启动信息，不记录健康负载和凭据。

手动运行或开发时：

```sh
python3 scripts/run.py serve
python3 scripts/run.py status
```

通过 `WATCHBRIDGE_HOME` 可以显式指定不同的私有数据目录。服务默认监听本地网络 TCP 8765，只提供 HTTPS 写入接口；不提供网络健康数据读取接口。

## iPhone 安装

1. 在 Mac 安装 Apple 官方 Xcode。需要完整 Xcode，单独的 Command Line Tools 没有 iOS SDK。
2. 打开 `ios/WatchBridge.xcodeproj`。
3. 在 Signing & Capabilities 选择自己的开发 Team；如 Bundle ID 冲突，将 `local.watchbridge.personal` 改为自己唯一的 ID。
4. 连接并信任自己的 iPhone，按 Xcode 提示开启开发者模式，选择真实 iPhone 后运行。
5. 保留 HealthKit 与 HealthKit Background Delivery 能力。安装签名和能力是否可用以实际 Apple 开发 Team 为准；本项目不包含任何他人的签名凭据。

模拟器不能替代真实健康数据与后台同步验收。

## 配对与首次同步

在 Mac 运行：

```sh
python3 scripts/pair.py
```

它会在本机生成二维码并打开。手机和 Mac 连接同一 Wi‑Fi，用 iPhone 系统相机扫码；健康桥会展示目标 Mac，点「确认配对」。链接五分钟有效，只能使用一次。二维码仅在本地生成，包含短期配对码，不发布到网络。

也可运行 `python3 scripts/run.py pair` 复制配对链接，在 App 中粘贴。若 Mac 有多个网卡，可用 `--endpoint https://你的局域网IP:8765` 显式指定；不能使用普通 HTTP。

配对后选择所需项目，点「授权并同步」，允许系统健康读取权限与本地网络访问。首次同步保持手机解锁、App 打开。Mac 防火墙如询问 Python 的传入连接，需要允许本地网络连接。

后台更新由 iOS 决定，锁屏、低电量、手机被强退、Mac 休眠或不在同一网络时可能延后。打开 App 或点「立即同步」可以补齐，不能承诺精确时刻运行。

## 在 Codex 查询

安装器已添加三个只读工具，重新加载 MCP 或重开本聊天后使用：

- `watchbridge_status`：先查看可读指标、时间范围和最近同步时间。
- `watchbridge_day`：按北京时间读某天某指标的原始记录，最多每页 500 条。
- `watchbridge_records`：指定带时区的起止时间和来源；返回 `next_offset` 供继续分页。

可以问：「检查健康桥连接」「查看昨天来自 Apple Watch 的心率记录」。查询结果会进入当前对话和所使用的模型服务；本地存储不意味着 AI 查询结果永不发送给模型提供方。

## 停止、撤销与备份

App 中的「暂停同步」只暂停，不删除历史记录。

查看已配对设备并撤销某台手机：

```sh
python3 scripts/run.py status
python3 scripts/run.py revoke 设备UUID
```

撤销立即阻止后续上传；保留数据库。替换 Mac 后，旧 Mac 上的令牌需要在旧 Mac 撤销。

停止服务（以你自己的用户会话编号替换 UID）：

```sh
launchctl bootout gui/UID ~/Library/LaunchAgents/local.watchbridge.sync.plist
```

如需彻底停用，移除该 LaunchAgent，并用 `codex mcp remove watchbridge` 移除查询入口。数据库目录由你决定是否保留；项目不自动删库。备份前先停服务，再复制完整私有数据目录（含 SQLite WAL、证书、私钥）。备份同样包含敏感健康数据，应由本人保护。

## 验证

```sh
python3 -m unittest discover -s tests -v
python3 -m tests.test_swift_transport
xcrun swiftc -frontend -parse ios/WatchBridge/*.swift
xcodebuild -project ios/WatchBridge.xcodeproj -scheme WatchBridge -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

前两项仅使用临时合成数据。Swift 传输测试编译并调用与 iPhone 共用的网络源码，实际测试 TLS 配对、错误证书拒绝、鉴权上传和确认，不伪装成真机 HealthKit 测试。

完整 iOS 构建、UI、HealthKit 真机、后台更新、签名验证仍需要 Xcode 与自己的 iPhone。参见 [PRODUCT.md](PRODUCT.md)、[UX-CONTRACT.md](UX-CONTRACT.md)。

## 文件结构

- `ios/`：完整 Xcode 工程与 SwiftUI、HealthKit、Keychain、HTTPS 客户端。
- `watchbridge/`：HTTPS 接收、SQLite、CLI、只读 MCP。
- `scripts/`：安装器、本地二维码、稳定运行入口。
- `tests/`：事务、鉴权、删除、时区、分页、MCP 及 Swift/TLS 合成测试。

CI 会检查服务端测试、Swift/TLS 传输和 iOS 模拟器构建。实际结果以 [GitHub Actions](https://github.com/zxycode7/watch-health/actions) 为准；原生健康读取、签名和后台同步仍需真机验收。App 尚未上架 App Store。
