# 健康桥原生交互契约

业务来源：[PRODUCT.md](PRODUCT.md)，来自用户明确要求的自研、本地控制和本人健康数据读取场景。

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | SwiftUI Form + SecureField | PRODUCT.md 权限与连接 | native | 真机 XCUITest 已验证有效草稿、确认按钮与配对成功 |
| Select/Listbox | SwiftUI Picker.menu | DESIGN.md Components | native | 补录范围，真机待验收 |
| Feedback | SyncModel.message + 原生 Text/ProgressView | PRODUCT.md 同步与保留 | persistent | 服务端失败路径测试；真机连接失败提示与首次同步完成已验证 |

配对成功关闭 Sheet 并回到首页；失败留在 Sheet，保留输入并显示恢复提示。地址、长期令牌不写日志；长期令牌仅 Keychain。二维码中的一次性配对码仅为本地展示的短期引导设计，不是长期登录凭据。

配对弹窗使用携带草稿的 item 呈现，输入状态由 `PairingSheet` 自己持有。链接为空或无效时明确解释不能确认的原因；有效链接显示目的主机和指纹。Debug 构建允许受信开发启动参数送入草稿或请求健康授权，仍保留配对确认与 iOS 健康授权，不在 Release 中启用。

授权流程完成不等于全部指标可读。关闭指标暂停后续读取；没有自动删库副作用。同步失败时保留已提交 anchor，未确认的批次下次重读。重复提交通过按钮禁用和 SyncModel 串行执行避免。

2026-10-17 真机验收已通过 XCUITest 操作本人 iPhone，完成配对、所选七项读取主题及系统历史范围确认、首次前台同步。已核对 Mac 样本归属与真机设备 ID 一致，包含 Watch 来源，并通过只读 MCP 查询验证。截图、设备日志、样本、签名及临时配对参数均留在本地私有验证目录，不随源码发布。

不含网页表格、搜索、网页弹窗、浏览器路由或滚动条主题；这些网页能力不适用。系统原生 Form、Sheet、Picker 和 ScrollView 管理焦点、触摸、可访问性和滚动，iOS 17+ 为运行契约。

真机验收：窄屏与辅助功能大字、VoiceOver、配对过期、证书变化、Mac 离线、拒绝部分健康权限、锁屏、前后台切换、增量重试、暂停恢复，以及补录与删除传播。
