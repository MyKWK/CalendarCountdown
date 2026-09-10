# iPhone / iPad 实施计划

macOS、iPhone、iPad 是**同一个产品**。macOS 仍是主桌面端；移动端补齐同一套四模块，而不是另做一个 App。

一级导航（代码顺序）：**倒数日、任务清单、使命清单、打卡**。不要把倒数日藏进「更多」，也不再使用「今天、任务、使命、打卡、倒数」那套旧一级导航。

## 阶段状态

| Gate | 内容 | 状态 |
|---|---|---|
| 0 | 共享合同：CloudKit payload 不含 EventKit ID；隐藏日历本机；单 DatabasePool；备份排除 | 代码已落地（本分支基于 1.x `02af78a` 的 sqlite3 实现，不是本机未提交的 GRDB 树） |
| 1 | `project.yml` / pbxproj 增加 iOS App、Widget、Tests、UITests；`TARGETED_DEVICE_FAMILY = 1,2` | 已落地 |
| 2 | iOS `@main`、Info.plist、entitlements、Launch Screen、App Group | 已落地 |
| 3 | iPhone `TabView` 四入口 | 已落地 |
| 4 | iPad 三列 `NavigationSplitView` | 已落地 |
| 5 | 任务 / 使命 / 打卡 CRUD 与深链 `calendarcountdown://` | 已落地（最小 CRUD） |
| 6 | iOS Widget 读 App Group snapshot | 已落地 |
| 7 | iPhone + iPad Simulator `xcodebuild` | **未在本环境执行**（无 Xcode） |
| 8 | 双模拟器 CloudKit | **未验收** |
| 9 | 真机 / TestFlight / Production CloudKit | **未验收** |

## 本环境不能代替的命令（需 macOS + Xcode）

```bash
cd Source
./Scripts/bootstrap.sh

xcodebuild -project CalendarCountdown.xcodeproj -list
xcodebuild -project CalendarCountdown.xcodeproj -scheme CalendarCountdowniOS -showdestinations

xcodebuild -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdowniOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdowniOS \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  CODE_SIGNING_ALLOWED=NO test
```

成功标准：`xcodebuild -list` 出现 `CalendarCountdowniOS`；`-showdestinations` 出现 iOS Simulator；iPhone/iPad destination 构建退出码不是 70。

## CloudKit 两个 P0

1. `AppDatabase.recordFetchOutcome(.failed)` 不得写入 `lastFetchAt`；`CloudKitSyncEngine.syncNow()` 在 fetch 失败时抛错并保持游标。
2. `AppBroker` / `CloudKitSyncEngine` 必须持有 `CloudProfileSession`，没有无 session 的 convenience 构造。
