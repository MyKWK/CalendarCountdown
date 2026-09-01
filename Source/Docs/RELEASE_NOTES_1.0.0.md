# 日历倒数 1.0.0

首个面向 GitHub 的公开版本。

## 主要能力

- 读取现有 Apple 日历来源、分类、事件和颜色。
- 选择单次事件、同名年度事件或本工具创建的事件参与倒数。
- 支持单次重要日、公历年度纪念日、农历年度纪念日和提前提醒。
- 提供主窗口、菜单栏最近倒数和 WidgetKit 桌面小组件。
- App、菜单栏和 WidgetKit 小组件跟随 macOS 语言，支持简体中文、英语、日语、韩语、西班牙语和俄语。
- 自动维护版本化 `tracked-events.json`，记录当前可见追踪项的开始年份、月日、历法、循环方式、闰月策略和 Apple 日历关联信息。
- App 一键导出追踪清单；CLI 支持 `tracking list`、`tracking refresh` 和 `tracking export`。
- CLI 提供 Apple 日历查询、录入、批量导入、预演和诊断能力。

## 数据边界

Apple 日历是事件内容的事实源。App 不建立第二套日历数据库；追踪 JSON 仅保存倒数选择所需的便携索引。公开 DMG 不包含任何真实用户或开发者的私人纪念日数据。

## 分发状态

当前 macOS Universal（arm64 + x86_64）DMG 使用 ad-hoc 签名，已验证包内签名完整性，但没有 Developer ID Application 证书和 Apple 公证。首次启动可能需要通过 Finder 的“打开”或“隐私与安全性”确认。
