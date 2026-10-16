# 健康桥原生交互契约

业务来源：[PRODUCT.md](PRODUCT.md)，来自用户明确要求的自研、本地控制和本人健康数据读取场景。

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | SwiftUI Form + SecureField | PRODUCT.md 权限与连接 | native | Swift 源码检查；iPhone 真机待验收 |
| Select/Listbox | SwiftUI Picker.menu | DESIGN.md Components | native | 补录范围，真机待验收 |
| Feedback | SyncModel.message + 原生 Text/ProgressView | PRODUCT.md 同步与保留 | persistent | 服务端失败路径测试；原生 UI 待验收 |

配对成功关闭 Sheet 并回到首页；失败留在 Sheet，保留输入并显示恢复提示。地址、长期令牌不写日志；长期令牌仅 Keychain。二维码中的一次性配对码仅为本地展示的短期引导设计，不是长期登录凭据。

授权流程完成不等于全部指标可读。关闭指标暂停后续读取；没有自动删库副作用。同步失败时保留已提交 anchor，未确认的批次下次重读。重复提交通过按钮禁用和 SyncModel 串行执行避免。

不含网页表格、搜索、网页弹窗、浏览器路由或滚动条主题；这些网页能力不适用。系统原生 Form、Sheet、Picker 和 ScrollView 管理焦点、触摸、可访问性和滚动，iOS 17+ 为运行契约。

真机验收：窄屏与辅助功能大字、VoiceOver、配对过期、证书变化、Mac 离线、拒绝部分健康权限、锁屏、前后台切换、增量重试、暂停恢复，以及补录与删除传播。
