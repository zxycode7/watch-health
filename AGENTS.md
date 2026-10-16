# 项目协作指南

## 目标与范围

本仓库是健康桥 WatchBridge 的开发源。产品约束见 `PRODUCT.md`，界面约束见 `DESIGN.md` 与 `UX-CONTRACT.md`。目标是本人 iPhone HealthKit → 本人 Mac → 只读 MCP，不引入第三方导出 App 或托管健康数据平台。

## 开始前

- 阅读相关实现、测试与文档，依据实际代码和验证结果判断问题。
- 保留与当前任务无关的已有改动；限制改动范围，不做无关重构。
- Mac 安装后的运行目录是部署副本，不能替代本仓库作为开发源。

## 核心约束

- HealthKit 只读；不把授权流程结束当作全部读取授权成功。
- 手机收到完整上传确认后才保存 anchor；失败重试不得跳过数据。
- 样本以 UUID 去重，删除按设备归属处理，批次提交保持事务性。
- 保留原始来源、单位和时间；空记录不是 0，跨来源不能直接相加。
- 保持证书固定校验、令牌哈希、Keychain 和只读 SQLite/MCP 边界。
- 数据库、私钥、令牌、配对二维码、个人健康导出和签名文件不属于源码。

## 验证

在仓库根目录运行：

```sh
python3 -m unittest discover -s tests -v
```

Mac 环境还可运行：

```sh
python3 -m tests.test_swift_transport
xcrun swiftc -frontend -parse ios/WatchBridge/*.swift
```

完整 Xcode/iOS SDK 环境运行：

```sh
xcodebuild -project ios/WatchBridge.xcodeproj -scheme WatchBridge -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

提交前审查最终差异，运行相关检查。仅报告实际执行结果；模拟数据测试和模拟器构建不能替代真机 HealthKit、权限、签名和后台行为验证。

## 回复

用中文简要说明改动、依据和验证结果，区分已确认事实、推断和未解决的问题。
