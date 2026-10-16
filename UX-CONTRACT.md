# 维律 Veyra 原生交互契约

业务来源：[PRODUCT.md](PRODUCT.md)，来自用户明确要求的自研、本地控制和本人健康数据读取场景。

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | SwiftUI Form + SecureField | PRODUCT.md 权限与连接 | native | 真机 XCUITest 已验证有效草稿、确认按钮与配对成功 |
| Select/Listbox | SwiftUI Picker.menu | DESIGN.md Components | native | 补录范围，真机待验收 |
| Feedback | SyncModel / DesktopModel persistent state | PRODUCT.md 同步与保留 | persistent | 服务端失败路径测试；真机连接失败提示与首次同步完成已验证 |
| Navigation | TabView + independent NavigationStack / NavigationSplitView | DESIGN.md | phone / desktop | 真机三页导航；Mac 侧栏实际点击 |
| Table Selection | Native SwiftUI Table selection | PRODUCT.md 原始查询 | one-record | Mac 实际记录、展开 UUID 与来源 |
| Date | Native SwiftUI Picker + Beijing locale | PRODUCT.md 半开区间 | 7/30/90/365 days / all | Swift 数据库边界测试 |
| Scrollbar | Native List / Table / ScrollView | DESIGN.md | table-owned / document | Mac 分页与自然滚动 |

配对成功关闭 Sheet 并回到首页；失败留在 Sheet，保留输入并显示恢复提示。地址、长期令牌不写日志；长期令牌仅 Keychain。二维码中的一次性配对码仅为本地展示的短期引导设计，不是长期登录凭据。

配对弹窗使用携带草稿的 item 呈现，输入状态由 `PairingSheet` 自己持有。链接为空或无效时明确解释不能确认的原因；有效链接显示目的主机和指纹。Debug 构建允许受信开发启动参数送入草稿或请求健康授权，仍保留配对确认与 iOS 健康授权，不在 Release 中启用。

授权流程完成不等于全部指标可读。关闭指标暂停后续读取；没有自动删库副作用。同步失败时保留已提交 anchor，未确认的批次下次重读。重复提交通过按钮禁用和 SyncModel 串行执行避免。

2026-10-17 真机验收已通过 XCUITest 操作本人 iPhone，完成配对、所选七项读取主题及系统历史范围确认、首次前台同步。已核对 Mac 样本归属与真机设备 ID 一致，包含 Watch 来源，并通过只读 MCP 查询验证。截图、设备日志、样本、签名及临时配对参数均留在本地私有验证目录，不随源码发布。

不含网页表格、搜索、网页弹窗、浏览器路由或滚动条主题；这些网页能力不适用。系统原生 Form、Sheet、Picker 和 ScrollView 管理焦点、触摸、可访问性和滚动，iOS 17+ 为运行契约。

真机验收：窄屏与辅助功能大字、VoiceOver、配对过期、证书变化、Mac 离线、拒绝部分健康权限、锁屏、前后台切换、增量重试、暂停恢复，以及补录与删除传播。

## Veyra 0.2 两端原生工作流

业务依据：用户 2026-10-17 明确要求品牌与图标升级、Mac 的 MCP 和数据客户端、手机各处优化、底层数据探索。兼容标识和只读 / 权限 / 留存约束继续来自 PRODUCT.md。


Mac 只通过 SQLITE_OPEN_READONLY 打开本项目数据库，参数绑定防止筛选值变为 SQL。100 条一页；指标、来源、日期变化归零分页，显式刷新重读当前条件；异步查询用版本号忽略旧结果。加载时清除前一查询的数据，避免把旧值套进新指标。表格与图表共用当前页，始终说明不是完整时间汇总。

MCP 控制台只读取维律配置状态，不展示其他 MCP 的密钥。实际运行 initialize、tools/list、status 后才显示检测通过。配置复制不包含健康值或令牌。网络接收在线与 MCP 可查询是两个独立状态。

配对二维码在内存和本机原生 CoreImage 中生成，五分钟后变为过期状态；关闭即清除页面中的链接。停止接收需说明手机暂时不能上传，保留已有记录和只读查询。安装 / 更新服务先备份运行文件和 SQLite 一致性快照，保留配置、证书与配对。

手机数据页读取最近 30 条样本，不冒充 Mac 入库状态或完整每日统计。来源信息可展开，用户可区分最新值、单位、时间与设备。28 项中的新增类型默认关闭。百分数统一以 0–100 表示，并记录 unit_convention；旧版尚无这些百分数数据时无需迁移，已有旧版百分数记录需补录后统一。

同步停止只在已确认页的边界停止；尚未完整确认的页不推进 anchor。后台使用 HealthKit observer 和 BGAppRefreshTask；取消和系统时间耗尽保留进度，15 分钟只是最早请求机会，不能承诺执行时刻。锁屏后台行为仍需长期真机验收。

原生控件承担键盘焦点、VoiceOver、减少动态效果与滚动条。项目无浏览器路由、CSS、网页验证弹窗、远程搜索或 CRUD 删库功能，这些网页专项能力不适用。应用内浅色 / 深色选择不改变操作系统设置。
