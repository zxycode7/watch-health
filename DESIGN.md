---
version: alpha
name: "健康桥"
description: "把个人健康记录送回自己 Mac 的中文原生工具"
colors:
  primary: "#135C54"
  background: "#F2F2F7"
  surface: "#FFFFFF"
  text: "#000000"
  danger: "#FF3B30"
typography:
  sans:
    fontFamily: "SF Pro, PingFang SC"
  mono:
    fontFamily: "SF Mono"
rounded:
  DEFAULT: "18px"
spacing:
  section-gap: "20px"
components:
  card: {}
  button: {}
  dialog: {}
---

# 健康桥 Design System

## Overview

参考真实设备之间的连接状态面板：让「连接哪台 Mac、同步到哪一步」一眼可见。用户是本项目所有者，主要在 iPhone 上配对、选择范围和确认同步状态。目标是中文产品工具，不涉及营销页或医疗诊断界面。

唯一的识别元素是 iPhone — 连接 — Mac 的设备行；没有模拟心电图、虚构数据或装饰图表。首次打开展示真实未配对状态。

运行时 token 的唯一所有者为 `ios/WatchBridge/Theme.swift`（Model B），本文件记录其语义。iOS 系统颜色与 Dynamic Type 承担深色模式、对比度、中文排版适配。没有网页 CSS 或第二套主题。

## Colors

主操作使用深青绿 primary，正文与表面使用系统语义色。上列 surface、text 和 background 是 iOS 浅色模式基线；深色模式由系统映射。错误同时有明确文字，不能仅靠红色识别。

## Typography

标题使用圆角系统大标题，正文使用系统默认字体，地址、指纹及数量使用 SF Mono。所有字号采用语义 text style，允许 Dynamic Type。中文界面和辅助功能标签统一简体中文，日期按北京时间显示。

## Layout

纵向 ScrollView，页面及卡片间距 20pt，卡片内边距 20pt。内容遵守系统安全区域，不固定屏幕高度。连接、同步、数据范围和补录为四个连续任务区。长文与错误自然换行。

## Elevation & Depth

系统 grouped background 与白色/深色语义卡片建立层级，不叠加人工阴影、渐变、玻璃效果。

## Shapes

卡片圆角 18pt。Button、Toggle、Picker、Form 和 Sheet 的外观及焦点归系统管理。

## Components

`BridgeCard` 负责全部内容容器；`BridgeTheme` 负责共享颜色、字号及间距。配对由原生 Sheet/Form 承载，配对链接默认掩码，显示目标主机和部分证书指纹供核对。Picker 明确选择系统原生菜单。

操作名称固定为「配对 Mac」「确认配对」「授权并同步」「立即同步」「补录并合并」。配对失败保留输入，授权和同步期间禁用重复提交。忙碌时显示系统 ProgressView 及实际发送条数，不伪造百分比。状态和错误保留在同步卡片中；关键反馈不依赖短暂 toast。

SF Symbols 只表达设备、连接和同步状态，图标旁保留文字。按钮使用原生触摸、键盘和 VoiceOver 语义。无装饰动画，系统负责减少动态效果。

## Do's and Don'ts

- 保留真实来源、空状态和失败恢复提示。
- 连接与同步操作由用户明确触发；不会在扫描链接后悄悄替换目的地。
- 不渲染假健康数值或把记录条数解释为健康指标。
- 不用固定字号或固定高度裁剪中文、错误和辅助功能大字体。
