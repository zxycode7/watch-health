# 维律 Veyra

开发仓库：[zxycode7/watch-health](https://github.com/zxycode7/watch-health)。协作约定见 [AGENTS.md](AGENTS.md)。

**自己的 iPhone App → 自己的 Mac → 本地只读 MCP。** 无第三方导出 App、云服务、API 密钥或运行时第三方依赖。Swift 使用 Apple SDK；Mac 使用 Python 标准库。

Apple Watch 的记录先通过 Apple 系统同步到 iPhone，再由维律读取。当前版本不需要额外安装手表 App。

## 0.2 目前能做什么

- 选择同步 28 类指标：原有心率、睡眠和活动之外，新增心率恢复、最大摄氧量、步行心率、静息能量、距离、楼层、站立、步态、日照、环境与耳机声级、睡眠呼吸紊乱。新增项目默认关闭，选择后再授权。
- iPhone 的概览 / 数据 / 设置，最近样本曲线、来源与设备版本信息、补录、停止本次同步和外观设置。
- 原生 Mac 客户端：数据目录、只读原始表格、时间和来源筛选、100 条分页、原始采样图、设备配对二维码、服务控制与 MCP 控制台。
- 本地一次性配对、HTTPS 固定证书校验、Keychain 凭据。
- HealthKit 增量与删除同步；确认成功后才保存进度；UUID 去重。
- 默认读取最近 30 天，可补录 90 天、一年、全部历史。
- MCP 查询数据清单、某天记录、指定时间段记录，保留来源、单位和原始样本。

空数据不代表 0，也不证明用户拒绝了哪项健康读取权限。第一版不跨来源直接计算步数或睡眠总量。

## Mac 原生客户端

需要 macOS 14+。在有完整 Xcode 的开发机上构建：

```sh
python3 scripts/build_mac.py
open build/Veyra.app
```

安装到自己的 Applications 目录后即可从启动台打开。客户端只读已有 SQLite，不包含第三方运行时依赖。Mac 接收与 MCP 服务仍需要 Python 3.11+；可在客户端「存储与服务」安装 / 更新，或者使用下文 CLI。

MCP 控制台会实际检测初始化、工具列表和数据状态，同时核对 Codex 中注册的命令、参数、数据目录。只展示维律自己的配置。退出客户端不会停止独立 LaunchAgent。

## Mac 接收与 MCP 服务

需要 Python 3.11+，本机 Codex CLI。无需 pip 或 npm 安装。

在本项目目录执行：

```sh
python3 scripts/install_mac.py
```

安装器会将运行文件复制到 `~/Library/Application Support/WatchBridge/runtime/`，建立私有数据库与 TLS 证书，添加本人登录后启动的 LaunchAgent，并注册 `watchbridge` MCP。现有 Codex 配置先备份，只新增这一项。若检测到不同来源的同名配置或运行目录，会停止覆盖。

升级已有安装时运行 `python3 scripts/install_mac.py --upgrade`：先保存一致性 SQLite 备份和旧运行目录，再切换代码并重启服务；原证书、配对和客户端配置保留。备份在私有状态目录的 `backups/` 下。

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

它会在本机生成二维码并打开。手机和 Mac 连接同一 Wi‑Fi，用 iPhone 系统相机扫码；维律会展示目标 Mac，点「确认配对」。链接五分钟有效，只能使用一次。二维码仅在本地生成，包含短期配对码，不发布到网络。

也可运行 `python3 scripts/run.py pair` 复制配对链接，在 App 中粘贴。若 Mac 有多个网卡，可用 `--endpoint https://你的局域网IP:8765` 显式指定；不能使用普通 HTTP。

配对后选择所需项目，点「授权并同步」，允许系统健康读取权限与本地网络访问。首次同步保持手机解锁、App 打开。Mac 防火墙如询问 Python 的传入连接，需要允许本地网络连接。

「确认配对」只有收到完整有效链接后才可点击；链接为空或格式错误时，输入框下方会显示原因。首次允许本地网络后，若仍提示连接不到 Mac，可再次点「确认配对」。

部分系统版本的健康授权分为两页：先选择读取主题并点「继续」，再选择历史数据范围并点「允许」。允许读取全部历史后，App 首次仍只同步最近 30 天；更早记录通过「补录历史」读取。

后台更新由 iOS 决定，锁屏、低电量、手机被强退、Mac 休眠或不在同一网络时可能延后。打开 App 或点「立即同步」可以补齐，不能承诺精确时刻运行。

## 在 Codex 查询

安装器已添加三个只读工具，重新加载 MCP 或重开本聊天后使用：

- `watchbridge_status`：先查看可读指标、时间范围和最近同步时间。
- `watchbridge_day`：按北京时间读某天某指标的原始记录，最多每页 500 条。
- `watchbridge_records`：指定带时区的起止时间和来源；返回 `next_offset` 供继续分页。

可以问：「检查维律连接」「查看昨天来自 Apple Watch 的心率记录」。查询结果会进入当前对话和所使用的模型服务；本地存储不意味着 AI 查询结果永不发送给模型提供方。

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
swift test
xcrun swiftc -frontend -parse ios/WatchBridge/*.swift
xcodebuild -project ios/WatchBridge.xcodeproj -scheme WatchBridge -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

自动化存储和网络测试使用临时合成数据，真机 UI 检查读取本人已授权的真实记录。Swift 传输测试编译并调用与 iPhone 共用的网络源码，实际测试 TLS 配对、错误证书拒绝、鉴权上传和确认，不伪装成真机 HealthKit 测试。

本地已完成本人 iPhone 的签名安装、真机 UI 配对、系统健康读取授权、首次前台同步和只读 MCP 查询验证。后台更新、锁屏与长期稳定性仍需单独验收。验证快照见 [BUILD-STATUS.json](BUILD-STATUS.json)，交互约束见 [UX-CONTRACT.md](UX-CONTRACT.md)。

真机 UI 冒烟检查（先安装当前 App 并完成本人授权），显式传入自己的设备和 Team：

```sh
python3 scripts/test_iphone.py --device YOUR_DEVICE_ID --team YOUR_TEAM_ID
```

该检查实际操作真机三页导航、原始记录详情、能力说明与增量同步；不会自动切换健康权限或注入配对信息。结果包含个人界面，默认位于忽略提交的 `build/DeviceChecks/`。

## 底层数据调研

见 [Apple Watch 数据可行性与实施路径](docs/APPLE-WATCH-DATA-RESEARCH.md)。已核实 ECG、逐搏心跳序列、watchOS 运动采集与 SensorKit PPG 的公开接口和授权边界；本版仅实现常规样本扩展，未把探索项冒充成已可用功能。

## 文件结构

- `ios/`：完整 Xcode 工程、共享指标和主题、SwiftUI、HealthKit、Keychain、HTTPS 客户端。
- `macos/`：原生 Mac SwiftUI / Charts / 只读 SQLite 客户端与查询边界测试。
- `assets/brand/`：原创图标母版与生成说明。
- `watchbridge/`：HTTPS 接收、SQLite、CLI、只读 MCP。
- `scripts/`：安装器、本地二维码、稳定运行入口。
- `tests/`：事务、鉴权、删除、时区、分页、MCP 及 Swift/TLS 合成测试。

CI 会检查服务端测试、Swift/TLS 传输和 iOS 模拟器构建。实际结果以 [GitHub Actions](https://github.com/zxycode7/watch-health/actions) 为准；原生健康读取、签名和后台同步仍需真机验收。App 尚未上架 App Store。

底层兼容标识仍为 WatchBridge / watchbridge，包含已有 URL scheme、Keychain、数据目录、LaunchAgent 和三个 MCP 工具；更名不会要求重新配对或搬迁健康库。
