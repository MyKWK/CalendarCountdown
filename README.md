# CalendarCountdown · 日历倒数

> 一个原生 macOS 重要日期追踪工具：以 Apple 日历为事实源，同时为用户、小组件和 AI Agent 提供清晰、可移植的倒数与纪念日能力。

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

## 产品截图

<p align="center">
  <img src="Documentation/Images/app-window-demo.png" width="900" alt="日历倒数主窗口 Demo">
</p>

<p align="center">
  <img src="Documentation/Images/widget-demo.png" width="720" alt="日历倒数桌面小组件 Demo">
</p>

<p align="center">
  <img src="Documentation/Images/menu-bar-demo.png" width="420" alt="日历倒数菜单栏 Demo">
</p>

> 截图使用完全虚构的 Demo 日历、姓名和日期，不包含真实用户信息。

## 项目是什么

CalendarCountdown 不是另一套日历数据库。账户、日历、事件和颜色仍由 Apple 日历管理；本项目使用 EventKit 读写用户授权的日历，并专注于一件事：让真正重要的日子始终可见、可计算、可导出、可被自动化调用。

## 基础能力

- 读取用户授权的 Apple 日历，保留原生账户、分类和颜色。
- 追踪生日、纪念日、节日和不循环的重要日期。
- 支持公历与中国农历周年规则，包括闰月和农历月末回退策略。
- 按系统本地日历计算“今天”、“明天”和剩余天数。
- 原生 macOS App、菜单栏快览和 WidgetKit 桌面小组件。
- 支持将普通事件、公历生日和农历生日写入明确指定的 Apple 日历。
- 通过 App 一键导出当前追踪的重要日子。
- Universal Binary，同时支持 Apple Silicon 和 Intel Mac（macOS 14+）。

## 为什么适合 AI Agent

`calcount` 是一个可直接作为 Agent shell tool 使用的命令行界面。所有结构化命令都输出 JSON，不混入交互提示，并通过明确退出码区分参数错误、日历未授权和运行失败。

适合 Agent 的关键设计：

- **可预测读取**：列出日历、查询事件、读取最近倒数和追踪清单。
- **稳定 JSON 包装**：成功返回 `{ "ok": true, "data": ... }`，失败返回 `{ "ok": false, "error": { "code": ..., "message": ... } }`。
- **可审查写入**：写操作必须指定 Apple 日历；批量导入可先使用 `--dry-run`。
- **幂等导入**：导入文档可用 `externalId` 避免 Agent 重试时重复创建。
- **可携带上下文**：`tracked-events.json` 保留起始年、历法、月日、循环规则、下次发生日期和 Apple 日历关联标识。
- **本地优先**：无需服务器或云端日历副本；Agent 只访问当前 Mac 上用户已授权的 EventKit 数据。

常用读取和导出命令：

```bash
./calcount doctor
./calcount calendars list
./calcount events list --days 365
./calcount next --limit 10 --days 3653
./calcount tracking refresh
./calcount tracking list
./calcount tracking export --output tracked-events.json
```

Agent 可以直接用 `jq` 消费结果：

```bash
./calcount next --limit 5 | jq '.data[] | {title, eventDate, calendarTitle}'
```

写入前先预演批量导入：

```bash
./calcount import /path/to/import.json --dry-run
```

`calcount` 目前提供本地 CLI 合同，并未声称实现 MCP 服务器或远程 API；它可以被任意支持 shell tool calling 的 Agent 框架包装调用。

## 追踪清单 JSON

Apple 日历始终是事件内容的事实源。`tracked-events.json` 不是第二套日历数据库，而是当前可见追踪项的版本化、可导出索引。

每个记录包含：

- 稳定 UUID、标题和类型（生日、纪念日、重要日期或其他）。
- 起始年、月、日和公历/农历标记。
- 循环频率、循环历法和农历边界策略。
- 下次发生日期、时间、时区和全天标记。
- Apple 日历来源、分类、颜色和可重新关联的标识。
- 追踪方式、开始追踪时间和置顶状态。

完整的匿名示例见 [tracked-events.example.json](Documentation/tracked-events.example.json)。

## 安装

当前版本：**1.0.0**

1. 从 [GitHub Release 下载 CalendarCountdown-1.0.0-macos-universal.dmg](https://github.com/MyKWK/CalendarCountdown/releases/download/v1.0.0/CalendarCountdown-1.0.0-macos-universal.dmg)。
2. 将“日历倒数.app”拖入 Applications。
3. 启动 App 并授予 Apple 日历完全访问权限。

1.0.0 发布包目前采用 ad-hoc 签名，尚未经过 Apple Developer ID 签名和公证。首次运行可能需要在 Finder 中按住 Control 点击 App，然后选择“打开”。

## 从源码构建

需要 macOS 14+、Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd Source
./Scripts/bootstrap.sh
./Scripts/build.sh
xcodebuild -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO test
./Scripts/package-dmg.sh
```

## 数据与隐私边界

- 日历事件保存在 Apple 日历中，项目不运行自建云端日历服务。
- 追踪选择和 `tracked-events.json` 保存在本机，用于展示与用户主动导出。
- 写操作只作用于用户明确指定的 Apple 日历。
- 真实用户纪念日文件已通过 `.gitignore` 排除，不应提交到公开仓库或发布包。

## 当前边界

- 当前支持 macOS；iPhone App、iPhone 小组件和 CloudKit 规则同步属于后续阶段。
- 本项目不是 CalDAV 服务器，不复制 Apple 日历的账户与分类体系。
- 详细产品和数据合同见 [Documentation/PRODUCT.md](Documentation/PRODUCT.md)。

## 项目结构

- `Source/`：Swift 源码、XcodeGen 配置、测试和构建脚本。
- `Documentation/`：产品合同、安装说明和匿名 JSON 示例。
- `Releases/1.0.0/`：版本说明和 SHA-256 校验文件；DMG 通过 GitHub Releases 分发。

## 开源许可证

本项目采用 [MIT License](LICENSE)。
