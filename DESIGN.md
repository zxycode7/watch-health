---
version: alpha
name: "维律 Veyra"
description: "个人节律的本地数据空间；iPhone 与 Mac 原生应用"
colors:
  primary: "#385CD9"
  primary-dark: "#8FA8FF"
  ink: "#111E44"
  background: "#F2F2F7"
  surface: "#FFFFFF"
  text: "#000000"
  danger: "#BA1A1A"
typography:
  sans:
    fontFamily: "SF Pro, PingFang SC"
  display:
    fontFamily: "SF Pro Rounded, PingFang SC"
  mono:
    fontFamily: "SF Mono, PingFang SC"
rounded:
  DEFAULT: "22px"
spacing:
  section-gap: "20px"
components:
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
  button:
    textColor: "{colors.primary}"
  button-dark:
    textColor: "{colors.primary-dark}"
  dialog:
    textColor: "{colors.text}"
  cover:
    backgroundColor: "{colors.ink}"
  error:
    textColor: "{colors.danger}"
---

# 维律 Veyra Design System

## Overview

用户明确要求品牌升级、原创图标、原生 Mac 客户端和手机全面优化。维律是本人的健康记录工作台：iPhone 管理健康读取与同步，Mac 管理长期记录与只读 MCP。中文产品界面，时间按北京时间；不表现为医疗诊断软件。

视觉参考是精密仪器的秩序与个人档案的连续性。识别元素是珍珠白与钴蓝双带 V 形，位于深靛蓝底上。品牌色集中于封面和图标；工作区保持系统原生、安静、有明确数据边界。避免虚构心电图、医疗十字、健康评分、装饰性大数字或霓虹科技感。

运行 token 仍采用 Model B：`ios/WatchBridge/Theme.swift` 为两端唯一共享运行时所有者，Mac Swift Package 直接编译该文件。`Models.swift` 是两端指标标题、单位、分类与格式化的共同所有者；Python 接收端由目录一致性测试约束。

## Colors

浅色文字强调色为 #385CD9，深色文字强调色为 #8FA8FF；品牌底色 #111E44。实心主按钮在两种模式下都使用 #385CD9（BridgeTheme.actionFill）和白色文字，避免浅蓝底白字的对比度不足。运行时使用动态 UIColor / NSColor 适配，卡片、背景与正文使用系统语义色；frontmatter 的 surface、text、background 是浅色基线。

错误必须含恢复说明，连接状态同时有文字和符号。原始记录图表使用系统分类配色区分来源，不用红绿暗示医学判断。

## Typography

品牌、标题使用 SF Pro Rounded 与中文系统字体。正文使用原生语义字体，iPhone 支持 Dynamic Type；UUID、工具名、指纹、数值及配置使用等宽字体。Mac 主数值字号 48pt 表示实际记录数量，不能被理解为健康分数。长中文自然换行，关键来源与 UUID 可展开或选择复制。

## Layout

iPhone 使用三个独立 NavigationStack 的 TabView：概览、数据、设置。概览只保留连接和同步的主任务；数据提供最近原始样本与来源；设置管理 28 项范围、历史补录、外观和能力说明。

Mac 使用 NavigationSplitView，侧栏 210–235pt，窗口至少 940×650pt。概览是有滚动边界的档案目录；原始记录页面独占表格滚动，固定 100 条一页，筛选与翻页保持可见。MCP、设备、存储页面独立自然滚动，不受表格高度约束。

两端共用 20pt 间距、22pt 卡片圆角；品牌封面使用 26–28pt 圆角和更疏朗的内边距。这是业务命名的封面变体，不扩散至表格与表单。

## Elevation & Depth

系统表面负责明暗层级，不添加人工投影或玻璃层。图标的体积感只存在于品牌资产，不应用到数据控件。浅色、深色和跟随系统由用户在 App 内选择，不改变系统全局外观。

## Shapes

普通卡片 22pt。表格、选择器、开关、对话框、焦点、滚动条交由原生 SwiftUI / 平台管理。按钮可点击、禁用、忙碌状态使用原生语义。

## Components

| 语义角色 | 运行时所有者 | 消费方 |
|---|---|---|
| 动态文字强调色 | BridgeTheme.accent | 两端链接、导航、来源符号 |
| 实心主操作填充 | BridgeTheme.actionFill | 两端 borderedProminent 主按钮 |
| 品牌背景 | BridgeTheme.ink | 两端概览封面 |
| 背景和表面 | BridgeTheme.background / surface | 两端工作区、BridgeCard |
| 容器 | BridgeCard | 状态、连接、MCP、存储及目录 |
| 品牌标识 | BrandMark + assets/brand/VeyraMaster.png | 图标、两端封面、应用信息 |
| 指标语义与格式 | HealthMetric | 手机列表、Mac 表格、图表、设置 |

配对继续使用 PairingSheet 和 item 草稿状态；不因更名更改 bundle ID、Keychain service、URL scheme、数据库目录或 MCP 工具名。原始数据图表始终说明范围及来源，点图表示采样，区间图表示时段，不暗示连续波形或跨来源去重汇总。

## Do's and Don'ts

- 显示真实数据、空记录原因、加载与恢复路径。
- 筛选清空分页；旧异步结果不能覆盖新条件；手动刷新更新当前查询。
- 保留只读 MCP、证书固定、Keychain、确认后保存 anchor 的边界。
- 新数据项目默认关闭，选择后再走系统健康授权。
- 不把 SDK 有接口解释为本设备、当前区域一定有数据；能力边界写清已接入与探索项。
- 不把个人健康样本、二维码、签名、真机日志或界面截图提交到 GitHub。
