# 日历倒数 · App Group 与 CloudKit 容器清单

同一套产品跨 Mac / iPhone / iPad 使用同一 App Group 和同一 iCloud 容器。iPhone 与 iPad 不是独立 App Store 产品。

| 用途 | 标识符 |
|---|---|
| App Group | `group.app.calendarcountdown.CalendarCountdown` |
| 旧版 App Group（仅迁移读取） | `group.com.hashxjhuang.CalendarCountdown` |
| CloudKit 容器 | `iCloud.app.calendarcountdown.CalendarCountdown` |
| macOS App | `app.calendarcountdown.CalendarCountdown` |
| macOS Widget | `app.calendarcountdown.CalendarCountdown.Widget` |
| iOS App | `app.calendarcountdown.CalendarCountdown.ios` |
| iOS Widget | `app.calendarcountdown.CalendarCountdown.ios.Widget` |
| URL scheme | `calendarcountdown` |

## SQLite 位置

- 共享库：`SharedContainer.rootURL()/calendarcountdown-v2.sqlite`
- iOS：必须位于 App Group 容器；打不开即失败，不回退到 Application Support
- iCloud 账号隔离：`Profiles/<accountHash>/calendarcountdown-v2.sqlite`
- 文件策略：`isExcludedFromBackup = true`；iOS 另设 `completeUntilFirstUserAuthentication`
- 进程内同一标准化路径只 intern 一个连接

## CloudKit 记录（倒数意图，不是日历副本）

上传：`CDManagedEvent`、`CDCountdownSelection`、`CDCountdownPreferences`（仅置顶）。

不上传：EventKit `eventIdentifier` / `calendarIdentifier`、日历事件正文、隐藏日历列表。隐藏日历只存在 `countdown_hidden_calendars` 本机表。
