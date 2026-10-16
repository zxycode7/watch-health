# Apple Watch 更底层数据：可行性与实施路径

调研日期：2026-10-17（北京时间）。结合 Apple 官方文档、当前安装的 Xcode SDK、开源仓库和本人真机读取验证。本文不包含个人样本、账号、设备 UUID 或签名信息。

## 结论

能拿到更多，而且本轮已经扩大了真实数据覆盖。需要把「还未接入的已有数据」「有公开序列接口」「需要 watchOS 主动采集」「需特殊研究授权」分开。硬件支持不保证系统已产生记录，也不保证普通第三方 App 有读取入口。

维律 0.2 已接入 28 类指标，真机已完成实际读取验证。具体个人记录数量与分布仅留在本地。没有记录的类型仍保持空状态，不能断言是地区锁定或授权被拒绝。此验证只说明这些记录能通过本人 HealthKit 读取，不证明所有表款、系统或地区都能生成。

## 可行性地图

| 数据层 | 能获得什么 | 方式与限制 | 当前状态 |
|---|---|---|---|
| 常规原始样本 | 心率、SDNN、呼吸频率、血氧、睡眠阶段、手腕温度、VO₂ max、心率恢复、步态、日照、声级等 | HealthKit，需已有样本、设备支持与本人授权 | 已接入 28 类；真机读取通过 |
| 逐搏序列 | 相对序列起点的每次心跳时间及中断标记，可研究 RR 间隔 | HKHeartbeatSeriesQuery，读取已有 heartbeat series；不是全天连续 PPG | 已核实公开接口；尚未接入 |
| ECG 电压 | 已录制 ECG 的逐点电压、时间及相关采样信息 | HKElectrocardiogramQuery，不能替代手表上的 ECG 测量过程 | 已核实公开接口；尚未接入 |
| 实时运动信号 | 加速度、旋转率、姿态、重力等 | watchOS Core Motion；需独立手表端、实际采集会话、能力探测和耗电评估 | 调研完成；尚未开发 watchOS 端 |
| 原始 PPG 光学信号 | LED / 光电二极管相关光学样本、配套运动信息 | SensorKit 的 PPG sensor；需 Apple 批准的研究项目与专门 entitlement | 当前个人签名不可据普通 HealthKit 授权取得 |
| 备份数据库 | 已经存在于系统健康库中的更多结构和元数据 | 本人加密本地备份与版本相关解析；不产生缺失的传感数据 | 仅调研参考，未集成 |

## 地区限制需要重新核对

Apple 于 **2026-10-14** 宣布在中国大陆推出睡眠呼吸暂停迹象提示。官方列出的支持范围包括 Series 9 及后续、Ultra 2 及后续、SE 3 及后续，并有适用人群条件。应先核对表款、系统和健康 App 的实际设置，而不是沿用旧的国区不可用结论。[Apple 中国大陆公告](https://www.apple.com.cn/newsroom/2026/10/sleep-apnea-notifications-available-today-on-apple-watch/)

其他功能以 [Apple 当前 watchOS 功能可用性](https://www.apple.com.cn/watchos/feature-availability/) 为起点，再核对购买地区、具体型号、系统与设置。第三方 App 读取已有 HealthKit 记录，不等同于解锁系统尚未启用的传感器或 Apple 的医疗功能。维律本轮新增睡眠呼吸紊乱类型，是否生成和可读仍需在具体设备上确认。

## 优先接入的底层数据

### 逐搏心跳序列

Apple 的查询回调给出相对起点时间、是否前面有缺口以及完成状态。应保存原始偏移与缺口，只有相邻、有效且没有中断的心跳才能形成可分析间隔；不能把跨缺口的差值当正常 RR。当前 SDNN 指标不应被标成 RR 或原始光学波形。[HKHeartbeatSeriesQuery](https://developer.apple.com/documentation/healthkit/hkheartbeatseriesquery)

建议：先做只读序列预览，验证真实样本覆盖，再加入独立序列表和分页 MCP；把信号质量、采样窗口、有效间隔数量与统计量一同显示。适合探索个人节律和短时变化，不能凭单个数值输出疾病结论。

### 已有 ECG 波形

官方查询可以逐点返回已录制 ECG 的电压，并有完成与错误事件。因此无需从 PDF 识别曲线即可保存可复核的波形。接口读取的是已存在的 ECG，不是让 App 任意启动电极测量或绕过系统启用条件。[HKElectrocardiogramQuery](https://developer.apple.com/documentation/healthkit/hkelectrocardiogramquery)

建议：序列按原样本 UUID 建主记录，电压点按索引分块保存；确认全部分块落库再推进父样本 anchor。MCP 按窗口与点数分页。现有 metadata 上限 8KB，不应把整条波形塞进元数据或一次返回给模型。

## 需要 watchOS 采集端的方向

Core Motion 可为主动采集提供运动信号。Apple WWDC 文档介绍普通 CMMotionManager 的逐点更新，以及 CMBatchedSensorManager 在支持设备、训练场景中的批量高频更新；后者最高可到 800Hz 加速度、200Hz device motion，实际必须运行支持性检查，不能按所有手表统一承诺。[Apple WWDC23 Core Motion](https://developer.apple.com/videos/play/wwdc2023/10179/)，[CMBatchedSensorManager](https://developer.apple.com/documentation/coremotion/cmbatchedsensormanager)

可研究动作片段、训练姿态和节律。实施需要 watchOS App、明确开始/停止、时间同步、离线队列、WatchConnectivity 传输、真实耗电与热量测试。历史 HealthKit 样本不能反推出从未保存的高频加速度；不应为了常驻采集伪造锻炼会话。

SDK 还存在 CMHighFrequencyHeartRateData，官方将其定义为 1Hz 心率数据及置信度。它是处理后的心率数据结构，不是原始 PPG，也不能仅凭存在该类型就推断当前设备可全天持续读取。[官方类型说明](https://developer.apple.com/documentation/coremotion/cmhighfrequencyheartratedata)

## 原始 PPG 的真实限制

Apple 已公开 SensorKit 的 SRPhotoplethysmogramSample，可表达光学样本及配套数据。关键限制是系统授权：SensorKit 读取 entitlement 仅授予批准的研究项目，还需手动签名配置和本人授权。支付普通开发者年费本身不等于取得该 entitlement。[PPG sensor](https://developer.apple.com/documentation/sensorkit/srsensor/photoplethysmogram)，[研究授权配置](https://developer.apple.com/documentation/sensorkit/configuring-your-project-for-sensor-reading)

因此，当前可维护的个人 App 路线是先吃透 HealthKit 的样本与序列，再做手表端运动采集；原始 PPG 作为独立研究合作路径评估。本轮没有加入私有 API、越狱依赖或伪造授权。

## GitHub 项目参考

- [christophhagen/HealthDB](https://github.com/christophhagen/HealthDB)：解析从本人加密 iOS 备份提取的 healthdb_secure.sqlite，包含心跳序列、ECG 电压和部分内部元数据；README 的兼容证据主要是 iOS 16/17。内部格式未公开，当前 iOS 27 兼容性未验证。适合参考结构或恢复已有资料，不能据此宣称解锁传感器。未接入维律。
- [paigeshin/HKQueries](https://github.com/paigeshin/HKQueries)：含 HealthKit 心跳序列等查询示例，可对照理解。仅作示例参考，接口语义、权限、分页和落库应以官方文档及我们的测试为准；未作为依赖引入。

## 建议的开发顺序与验收

1. 本轮已完成：28 类目录、真机读取、来源与版本元数据、两端浏览、只读 MCP、服务备份升级。
2. 下一优先：逐搏心跳序列和已有 ECG。验收需真实序列、缺口保留、分块重试、删除传播、跨窗口分页与来源追溯。
3. 再做 watchOS 运动采集。验收需支持性探测、开始/停止、断连补传、时间对齐及连续使用耗电。
4. PPG 研究授权单独立项；在获得正式 entitlement 前只保留技术评估，不把它呈现为已可用功能。

更多采样只有在覆盖、单位、来源和缺失语义清楚时才更有用。当前不自动生成医疗判断或没有方法说明的“压力 / 恢复分”。
