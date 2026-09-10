# iPhone / iPad 验收返工说明

本文件是仓库内的返工入口。完整阶段表见 [IPHONE_IPAD_IMPLEMENTATION_PLAN.md](IPHONE_IPAD_IMPLEMENTATION_PLAN.md)，对外口径见 [IPHONE_IPAD_ACCEPTANCE_STATUS.md](IPHONE_IPAD_ACCEPTANCE_STATUS.md)。

## 必须保留的合同

- 倒数追踪意图可上云：`CDManagedEvent` / `CDCountdownSelection` / `CDCountdownPreferences`
- `CDManagedEvent` JSON 不含 `calendarIdentifier`
- `CDCountdownSelection` JSON 不含 EventKit `eventIdentifier` / `calendarIdentifier`
- `CDCountdownPreferences` 只上传置顶；隐藏日历留在本机表
- 同一路径只 intern 一个 SQLite 连接；库文件排除备份；iOS 使用 `completeUntilFirstUserAuthentication`
- 一级导航是倒数日、任务清单、使命清单、打卡

## CloudKit P0

- `recordFetchOutcome(.failed)` 不得写 `lastFetchAt`
- `CloudKitSyncEngine.syncNow()` 在 fetch 失败时抛错
- `AppBroker` 与 `CloudKitSyncEngine` 必须持有 `CloudProfileSession`

## 本 Git 分支范围

从公开仓库 `02af78a`（1.x macOS）落地 iOS target 与 sqlite3 共享底座。它**不是**本机未提交 GRDB 2.0 工作树的搬运。合并本机脏树时需要单独对账 Persistence 实现。
