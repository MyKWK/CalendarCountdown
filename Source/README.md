# CalendarCountdown（日历倒数）

一个以 Apple 日历为可见事件载体的 macOS 倒数日 App，包含菜单栏、桌面小组件和 AI 友好的 `calcount` CLI。

## 当前目标

- EventKit 日历读取、原生分类展示与指定日历写入
- 普通事件、公历生日、农历生日
- 菜单栏最近事件和桌面小组件
- JSON CLI 与批量导入
- 当前追踪清单自动维护为 JSON，并可在 App 中一键导出
- 为未来 iOS App 复用核心模型

产品边界见 [Docs/PRODUCT.md](Docs/PRODUCT.md)。

## 生成工程

```bash
brew install xcodegen
./Scripts/bootstrap.sh
open CalendarCountdown.xcodeproj
```

## 无签名编译验证

```bash
./Scripts/build.sh
```

## 本地安装 DMG

本机没有 Developer ID 时，可以生成 ad-hoc 签名的本地测试包：

```bash
./Scripts/package-dmg.sh
```

1.0.0 产物位于 `dist/CalendarCountdown-1.0.0-macos-universal.dmg`，内含 arm64 和 x86_64 可执行文件。当前构建采用 ad-hoc 签名，不等同于经过 Developer ID 签名和 Apple 公证的发行包。

要运行日历权限和小组件，需要在 Xcode 中为 App、Widget 和 CLI 配置同一个开发团队及 App Group：

```text
group.app.calendarcountdown.CalendarCountdown
```

## CLI 示例

```bash
calcount auth
calcount calendars list
calcount events list --days 90
calcount events add --calendar "个人" --title "项目上线" --date 2026-10-01 --alert-days 7,1,0
calcount birthdays add --calendar "生日" --name "小林" --lunar 8-15
calcount next --limit 10
calcount tracking list
calcount tracking export --output ~/Desktop/important-days.json
calcount import ./first-batch.json --dry-run
calcount import ./first-batch.json
calcount doctor
```

通用导入格式见 [Docs/first-batch.example.json](Docs/first-batch.example.json)，追踪清单格式见 [Docs/tracked-events.example.json](Docs/tracked-events.example.json)。真实用户导入数据属于本地私有资料，不进入公开仓库或发布包。
