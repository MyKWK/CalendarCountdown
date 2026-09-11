# CalendarCountdown iPhone / iPad 验收不通过与返工执行指南

> 文档状态：待 Grok 4.6 执行
>
> 编制日期：2026-09-10
>
> 适用工程：`/Users/hashxjhuang/CalendarCountdown`
>
> 当前分支：`grok/v2-p0-cloudkit-projection-broker`
>
> 当前基线：`02af78a` 加大量未提交的 CalendarCountdown 2.0 工作区
>
> 本文用途：解释本轮 iPhone/iPad 验收不通过的原因，规定返工顺序、完成标准和证据格式。
>
> 权威设计输入：`IPHONE_IPAD_IMPLEMENTATION_PLAN.md`、`TASK_MISSION_HABIT_BLUEPRINT.md`、`APP_GROUP_INVENTORY.md`、两份 `PRODUCT.md`。

---

## 1. 验收结论

当前工程不能表述为“iPhone/iPad 代码已经完成”。准确状态是：

> macOS 共享领域、SQLite 和部分 CloudKit/EventKit/Widget 基础设施已经实现；Core 48 项与 Persistence 26 项 macOS 测试通过。iOS App target、iOS Widget target、移动端测试 target、移动端生命周期、移动 UI 和移动端系统集成尚未落地。

本轮结论为：**移动端验收不通过，尚未达到可构建的 iOS 空壳门槛。**

这不否定已经完成的共享底座，但共享代码存在不等于 iPhone/iPad 产品已经实现。

---

## 2. 不通过的直接证据

### F0：工程中没有 iOS target（阻断级）

当前 `Source/project.yml`：

- 只配置 `macOS: "15.0"`；
- 8 个 target 全部是 `platform: macOS`；
- 没有 `CalendarCountdownMobile`；
- 没有 `CalendarCountdownMobileWidget`；
- 没有 `CalendarCountdownMobileTests`；
- 没有 `CalendarCountdownMobileUITests`；
- 没有 `TARGETED_DEVICE_FAMILY = "1,2"`；
- 生成的 `project.pbxproj` 只包含 `SDKROOT = macosx`。

当前命令结果：

```text
xcodebuild -project CalendarCountdown.xcodeproj -scheme CalendarCountdown -showdestinations

Available destinations:
  My Mac
  Any Mac
```

执行：

```bash
xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

当前会以退出码 70 失败：

```text
Unable to find a destination matching ... platform:iOS Simulator
```

因此现在既不能安装到 iPhone/iPad 模拟器，也没有移动端二进制可供验收。

### F1：没有移动端 App 生命周期和 UI（阻断级）

当前 `RootView` 的四个一级入口已经正确：倒数日、任务清单、使命清单、打卡。但它属于 macOS App target，不能替代以下移动端实现：

- iOS `@main` 和 scene lifecycle；
- iPhone 四个底部 tab 及各自独立的 `NavigationStack`；
- iPad 三列 `NavigationSplitView`、折叠和分屏状态；
- 移动端 toolbar、sheet、键盘避让和系统设置跳转；
- Dynamic Type、VoiceOver、深色模式和触控尺寸适配；
- 移动端深链冷启动与热启动恢复。

当前代码中没有 `TabView`、size-class 路由、`MobileContainerLocator` 或 `AppSession`。现有 App shell 仍依赖 `AppKit`、`NSApplicationDelegate`、`NSWindow`、菜单栏和桌面 Broker。

### F2：移动端配置与能力文件不存在（阻断级）

当前不存在独立的：

- iOS Info.plist；
- iOS App entitlements；
- iOS Widget Info.plist/entitlements；
- iOS App Icon/Launch Screen 配置；
- 移动端 URL scheme 注册；
- iOS/iPadOS deployment target；
- iPhone/iPad device-family 配置。

已有 macOS entitlement 不能证明移动端 App Group、CloudKit、Calendar 或 Reminders capability 已配置，更不能证明签名安装后有效。

### F3：74 项测试全部是 macOS 测试（阻断级）

2026-09-10 复跑结果：

```text
CalendarCountdownCoreTests:        48 passed
CalendarCountdownPersistenceTests: 26 passed
Total:                             74 passed
Platform:                          macOS
```

它们确认了共享底座的一部分行为，但没有覆盖：

- iOS 编译；
- App Group 容器真实 URL；
- iOS 文件保护属性；
- 模拟器杀进程/重启后的 SQLite；
- iPhone/iPad UI；
- 移动端 EventKit 权限和投影；
- 移动 Widget 安装后读取；
- 双模拟器 CloudKit 收敛；
- 真机、TestFlight 或 Production CloudKit。

### F4：共享 CloudKit 路径仍有两个 P0（阻断跨端同步）

在创建移动端 target 前，必须先关闭两个已确认的共享生产路径缺口：

1. `CloudKitSyncEngine.syncNow()` 在 `fetchChanges()` 返回后无条件写入 `lastFetchAt = Date()`；当 fetched record 解码或本地 apply 失败时，会覆盖“不推进 fetch 状态”的语义。
2. `AppBrokerServer.runSetCloudMode()` 在没有 engine 时直接创建 `CloudKitSyncEngine(workspace:)`，没有注入 `CloudProfileSession`；CLI/MCP 首次开启 iCloud 可以绕开账号 profile 隔离。

修复方向：

- `lastFetchAt` 只能由 fetched apply 的成功/空批次路径推进；失败时保留 inbox、错误和原 cursor 状态；
- App、Broker、CLI/MCP 必须共用唯一的 CloudKit engine 创建入口；任何生产 engine 开启 iCloud 模式前都必须绑定当前 `CloudProfileSession`；
- 为 engine 层增加可注入 transport/fake，不能只测 `CloudSyncService.ingestFetched`；
- 增加“Broker 首次启用 iCloud → 换号 → 回到原账号”的集成回归。

### F5：文档仍有旧口径残留（文档阻断）

虽然移动端导航章节已经规定四个一级入口，但 `TASK_MISSION_HABIT_BLUEPRINT.md` 第 10.1 节仍画有“今天 / 任务 / 使命 / 打卡 / 倒数”的旧一级导航，`IPHONE_IPAD_IMPLEMENTATION_PLAN.md` 仍保留独立的“今天”产品段落。

统一规则：

- 一级入口永远只有：倒数日、任务清单、使命清单、打卡；
- “今天”如果保留，只能是任务清单内部的筛选/摘要，不得成为第五个 tab 或第五个侧栏入口；
- 不设置“更多”一级入口，不把倒数放进“更多”；
- 更新所有权威文档中的图、章节标题、验收用例和截图说明，不能只修改 README。

### F6：当前实现尚未形成可追溯提交（交付阻断）

当前 `HEAD` 与现有远端分支均为 `02af78a`，CalendarCountdown 2.0 的大量代码和文档仍处于 modified/untracked 状态。

Grok 开始返工时必须保护这些工作：

- 禁止 `git reset --hard`、`git clean`、覆盖式 checkout 或删除未跟踪文件；
- 先记录完整 Git 状态、diff stat、未跟踪文件列表和基线测试结果；
- 先把现有共享底座保存为可追溯基线，再分阶段提交移动端改动；
- 未经用户明确授权，不推送、不合并、不改远端目标分支。

---

## 3. 已通过、必须保留的产品合同

返工不得破坏以下已经实现并通过本机测试的合同。

### 3.1 同一产品

- Mac、iPhone、iPad 按同一个 App 产品处理；
- macOS 是主力与先发平台；
- iPhone/iPad 共用一个 iOS App target，`TARGETED_DEVICE_FAMILY = "1,2"`；
- 不另开仓库，不复制一套业务实现，不创建第二套 schema；
- 不创建第二个 App Store 产品记录；如果 native target 的签名要求不同 bundle ID，也必须挂在同一 App Store Connect 应用记录下；
- Mac Catalyst 关闭，保留现有原生 macOS App。

### 3.2 四个一级入口

移动端和当前 macOS `RootView` 使用相同信息架构：

1. 倒数日
2. 任务清单
3. 使命清单
4. 打卡

设置、同步状态、权限和 Apple 日历入口均为二级路由。

### 3.3 倒数与 Apple 日历边界

Apple 日历继续是事件正文的内容事实源。CloudKit 同步的是本工具自己的逻辑记录：

- `CDManagedEvent`：本工具管理的规则，云 payload 去掉本机 `calendarIdentifier`；
- `CDCountdownSelection`：追踪意图，不上传 EventKit `eventIdentifier` / `calendarIdentifier`；
- `CDCountdownPreferences`：置顶；
- `countdown_hidden_calendars` / `untrackedCalendarIdentifiers`：只留在本机，不上传；
- EventKit identifier、Reminder identifier 和具体投影目的地只作为本机 binding；
- 不把 Apple 日历正文复制成第二套 CloudKit 日历。

### 3.4 App Group 与 SQLite

- 每台设备拥有自己的 SQLite 离线副本；跨设备同步走 CloudKit records，不共享 SQLite 文件；
- App 进程是本机数据库的唯一写入主体；
- 同一进程、同一标准化路径只 intern 一个 `DatabasePool`；
- SQLite、WAL、SHM、父目录和 `Backups/` 排除备份；
- iOS 使用 `completeUntilFirstUserAuthentication`；
- Widget 只读 App Group 中的派生 JSON 快照，不打开 SQLite；
- App Group container 获取失败必须显式报错，Release 不得偷偷退回 Widget 不可见的目录。

### 3.5 平台边界

- macOS 菜单栏、Broker、CLI、`NSApplicationDelegate` 和窗口管理不移植到 iOS；
- Core 不依赖 SwiftUI/EventKit/CloudKit/GRDB/AppKit/UIKit；
- Persistence/Services 不依赖 AppKit/UIKit；
- Apple bridge 不依赖 App UI；
- 共享 View 不直接 import AppKit/UIKit；平台差异由小型 adapter/capability 注入。

---

## 4. Grok 返工顺序

必须按以下 Gate 顺序推进。上一 Gate 未满足退出条件，不得把下一 Gate 写成“已完成”。

### Gate 0：冻结共享基线并修复 P0

工作：

- 保存当前未提交的 2.0 共享底座；
- 修复 `lastFetchAt` 错误推进；
- 统一 CloudKit engine 创建入口并强制 profile session；
- 增加对应 engine/Broker 集成测试；
- 重跑 macOS Core、Persistence、App/Widget/CLI/Broker 回归；
- 清理两份移动端权威文档中的第五入口残留。

退出条件：

- 两个 CloudKit P0 均有失败前、修复后测试；
- macOS 74 项现有测试不回归；
- macOS Debug test 与 Release 无签名 build 通过；
- 文档只保留四个一级入口；
- 形成独立、可追溯 commit。

### Gate 1：建立真实移动端工程拓扑

工作：

- 以 `Source/project.yml` 为工程配置事实源；
- 新增 `CalendarCountdownMobile`；
- 新增 `CalendarCountdownMobileWidget`；
- 新增 `CalendarCountdownMobileTests`；
- 新增 `CalendarCountdownMobileUITests`；
- 设置 iOS/iPadOS 18.0，device families 为 iPhone + iPad，关闭 Mac Catalyst；
- 增加移动端 Info.plist、entitlements、assets 和 launch 配置；
- 绑定同一个 CloudKit container 与 App Group；
- 重新执行 `xcodegen generate`，不得只手改 `project.pbxproj`。

共享 Core/Persistence/Services 可以由独立的 iOS build target 引用同一套源文件，也可以采用等价的多平台组织方式；禁止复制源代码形成第二套业务实现。

退出条件：

- `xcodebuild -list` 能看到四个移动 target；
- `-showdestinations` 能看到 iOS Simulator；
- Mobile 空壳能在 iPhone 17 Pro 和 iPad Pro 13-inch (M5) 启动；
- macOS 原有 target 和 scheme 仍存在并可构建。

### Gate 2：跨平台拆分与移动端容器

工作：

- 从 `CalendarBridge/EventKitRepository.swift` 去除 AppKit 颜色依赖，建立平台颜色 adapter；
- 把 AppKit lifecycle、菜单栏、窗口和 Broker 留在 macOS shell；
- 建立移动端 `AppSession`，装配 Workspace、CloudKit、EventKit、projection 和 snapshot；
- 建立 `MobileContainerLocator`，只使用正式 App Group URL；
- 让 Core/Persistence/Services/Apple bridge 在 iphonesimulator SDK 下编译；
- 在 iOS 测试中验证数据库、WAL/SHM、Backups 的备份排除和文件保护；
- 验证同一路径 pool intern、杀进程/重启持久化和 migration 失败恢复。

退出条件：

- iPhone/iPad Simulator 均能创建数据库并在重启后读回；
- Widget target 能读取 App 生成的同 profile 快照；
- Release 配置遇到 App Group 错配会失败并给出可诊断错误；
- macOS 数据路径和现有 1.x 导入不回归。

### Gate 3：完成 iPhone/iPad 导航与共享 UI

工作：

- iPhone 实现四个 tab，每个 tab 有独立 navigation path；
- iPad 实现 Sidebar/Content/Detail 三列结构和 compact collapse；
- “今天”仅作为任务内部筛选/摘要；
- 抽取共享 routes、App state、表单 validator 和 feature components；
- 增加 loading、empty、offline、syncing、conflict、permission-denied 和 error 状态；
- 完成旋转、分屏、键盘、Dynamic Type、VoiceOver、深色/高对比适配。

退出条件：

- iPhone 与 iPad 的四模块都能进入并保持路由；
- 没有第五个一级 tab，也没有“更多 → 倒数”；
- iPad mini 窄分屏与 13 英寸三列均无阻断布局问题；
- UI tests 覆盖冷启动、切 tab、深链、旋转/折叠和未保存 draft。

### Gate 4：完成离线 CRUD

工作：

- Task：创建、编辑、完成、重开、跳过、归档、删除、循环范围；
- Mission：创建、编辑、暂停、完成、归档、任务关联和进度解释；
- Habit：创建、编辑、打卡、补打、撤销、跳过和统计；
- Countdown：读取、追踪、取消追踪、置顶、隐藏本机日历、导入预览和导出；
- 所有写入进入同一 command/validation/idempotency/ifRevision 路径；
- UI 不直接执行 SQL。

退出条件：

- 关闭 CloudKit、拒绝 EventKit 权限时，四模块核心 CRUD 仍可离线完成；
- 杀进程并重启后数据和导航状态符合合同；
- iPhone/iPad service/integration tests 通过；
- 不产生第二套 schema 或移动端专用业务逻辑副本。

### Gate 5：完成 EventKit 与系统投影

工作：

- Calendar 与 Reminders 分时请求权限；
- 覆盖 notDetermined、denied、restricted、writeOnly、fullAccess；
- 完成倒数读取/追踪/创建/删除与农历规则；
- 完成 Task/Habit/Mission 的 desired projection、apply、remove、repair；
- 完成允许的原生反向动作；
- 通过稳定领域 URL 重连，不把 EventKit identifier 当跨设备主键；
- 目的地缺失时进入 `needsDestinationSelection`，不得写入默认日历。

退出条件：

- 在隔离测试 Calendar/Reminder List 完成创建、可见、修改、完成/重开、删除、重建；
- 连续 reconcile 三次不产生重复项；
- 权限拒绝或投影失败不丢 SQLite 核心数据；
- Apple 原生 App 中的结果有截图/记录证据。

### Gate 6：完成 CloudKit Development 双端复制

工作：

- 移动 App 启动、scene active、手动刷新和下次启动驱动补偿同步；
- 两个模拟器同账号验证首次同步、增量、删除、乱序依赖和冲突；
- 验证离线写入后恢复；
- 验证 iCloud A → 登出 → B → A 的 profile 隔离；
- Cloud apply 后刷新 UI、Widget snapshot 和 projection queue；
- 明确展示 outbox、inbox、conflict、last send/fetch 和可重试错误。

退出条件：

- 两个模拟器 SQLite 最终收敛；
- tombstone、deferred inbox、字段合并和账号隔离均有数据证据；
- CloudKit Console 中 development zone/record 有记录；
- 无静默丢弃、无账号串库、无错误推进 cursor。

### Gate 7：完成移动 Widget、深链与体验

工作：

- 实现倒数、今日任务、使命进度、今日习惯四类 Widget；
- iPad 支持 extra large；
- Widget 只读 App Group 快照；
- 点击 Widget 精确深链到模块/对象；
- 快照损坏、版本不兼容、profile 不匹配时显示可行动占位；
- 首版 Widget 操作优先深链回 App；若 extension 直接写库，必须先补跨进程互斥与幂等设计。

退出条件：

- 签名安装后的 App 与 Widget 具有相同 App Group；
- App 写入后 Widget 能读到正确 profile 快照并刷新；
- iPhone/iPad 各 family 截图与深链测试通过。

### Gate 8：模拟器正式验收

最低矩阵：

| 设备 | 必验重点 |
|---|---|
| iPhone 17e | 小屏、键盘、Dynamic Type |
| iPhone 17 Pro / Pro Max | 自动 smoke、横屏、大屏布局 |
| iPad mini (A17 Pro) | 折叠、窄分屏、触控密度 |
| iPad Pro 13-inch (M5) | 三列、extraLarge Widget、大画布 |

退出条件：

- iPhone 17 Pro 与 iPad Pro 13-inch 自动测试通过；
- 四设备里程碑人工验收完成；
- Core/Persistence/Services 至少在 iOS target 跑一次；
- UI、EventKit、Widget、migration、性能 smoke 均有证据；
- macOS App/Widget/CLI/Broker 回归通过；
- 所有 P0/P1 归零。

此时如果尚未完成 Gate 9，只能表述为：

> 移动端模拟器版本通过，真机和 Production 发布验收待完成。

### Gate 9：真机、Production 与发布

工作：

- 至少一台真实 iPhone 和一台真实 iPad 签名安装；
- 验证真实 Calendar/Reminders、App Group、Widget、后台系统机会、性能和内存；
- 部署 CloudKit production schema；
- 通过 TestFlight/Production CloudKit；
- 验证升级安装、数据迁移、账号切换、回滚和隐私说明；
- 更新版本、发布说明和支持文档。

退出条件：

- 真机与 Production 证据齐全；
- 文档未验收项归零；
- 只有到此处才允许表述“iPhone/iPad 版本完成并可发布”。

---

## 5. 每个 Gate 的强制工作方式

Grok 每次开始一个 Gate 前必须先输出：

1. 当前分支、HEAD、Git 状态和未跟踪文件；
2. 本 Gate 拟修改文件清单；
3. target/模块依赖变化；
4. 风险和不会触碰的范围；
5. 本 Gate 的验收命令。

每个 Gate 完成时必须输出：

1. 实际修改文件；
2. 测试命令、退出码、通过/失败数量；
3. iPhone/iPad/macOS 分平台结果；
4. 未验证项和原因；
5. 证据目录；
6. 对应 commit SHA；
7. 下一 Gate 是否满足启动条件。

禁止行为：

- 为了让测试变绿而删除现有测试或降低断言；
- 只修改 `project.pbxproj`，不修改 `project.yml`；
- 复制 Core/Services 形成 iOS 专用业务实现；
- 把 App Group 当跨设备同步；
- 把模拟器结果写成真机或 Production 结果；
- 没有证据就勾选 checklist；
- 未经授权推送、合并或清理工作区。

---

## 6. 关键验收命令

实际 scheme 和 bundle identifier 以 Gate 1 最终配置为准；如果调整命名，必须同步更新本文和实施计划。

### 6.1 工程拓扑

```bash
cd /Users/hashxjhuang/CalendarCountdown/Source
xcodegen generate
xcodebuild -project CalendarCountdown.xcodeproj -list
xcodebuild -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdownMobile \
  -showdestinations
```

必须看到 iOS Simulator destination，以及 Mobile App/Widget/Test/UI Test targets。

### 6.2 macOS 回归

```bash
xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

最低要求：现有 Core 48 + Persistence 26 不回归；新增测试另计，不得通过减少总数伪装成功。

### 6.3 iPhone 自动测试

```bash
xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdownMobile \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test
```

### 6.4 iPad 自动测试

```bash
xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdownMobile \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' \
  test
```

### 6.5 通用 iOS Simulator Release 编译

```bash
xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdownMobile \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 6.6 基础质量检查

```bash
cd /Users/hashxjhuang/CalendarCountdown
git diff --check
git status --short --branch
```

测试和构建使用独立 DerivedData/result bundle 目录，避免把产物混入源码提交。

---

## 7. 验收证据目录

每个里程碑保存：

```text
Documentation/Acceptance/Mobile/<date>-<commit>/
  REPORT.md
  environment.txt
  git-status.txt
  target-list.txt
  destinations.txt
  xcodebuild-macos.log
  xcodebuild-phone.log
  xcodebuild-pad.log
  cloudkit-development.md
  eventkit.md
  app-group-and-file-protection.md
  screenshots/
    iphone/
    ipad/
    widgets/
    permissions/
```

大型 `.xcresult` 可以放在外部归档位置，但 `REPORT.md` 必须记录绝对路径、测试时间、commit SHA、设备和退出码。

证据必须分别标注：

- source/build；
- macOS unit/integration；
- iOS Simulator unit/integration/UI；
- App Group/Widget；
- EventKit；
- CloudKit Development；
- iPhone 真机；
- iPad 真机；
- CloudKit Production/TestFlight；
- Git 提交与远端交付。

任何一层通过都不能自动替代下一层。

---

## 8. 对外状态口径

| 已达到状态 | 允许表述 |
|---|---|
| 只有共享 macOS 测试通过 | 共享底座本机测试通过；移动端未实现 |
| Mobile target 可编译启动 | 移动端工程空壳已建立；功能未完成 |
| 离线 CRUD 和移动 UI 通过 | 移动端离线核心功能通过；系统集成待验收 |
| 模拟器全部 Gate 通过 | 移动端模拟器版本通过；真机和 Production 待完成 |
| 真机与 Production 全部通过 | iPhone/iPad 版本完成并可发布 |

禁止使用模糊表述，例如“基本完成”“代码已经都有了”“理论上支持 iOS”。必须说清平台、环境、测试层和未验证项。

---

## 9. 最终完成定义

以下十项同时满足，验收方才可给出“移动端完成”：

1. 一个 iOS App target 同时支持 iPhone/iPad；
2. Core/Persistence/Services 复用同一源代码和 schema；
3. 四个一级入口与 macOS `RootView` 一致；
4. 四模块完整离线 CRUD 通过；
5. App Group SQLite、文件保护、Widget 快照通过；
6. EventKit Calendar/Reminders 权限、投影、反向动作和 repair 通过；
7. CloudKit Development 双模拟器同步、冲突、删除、乱序和账号隔离通过；
8. iPhone/iPad 模拟器矩阵与 macOS 回归通过；
9. 真实 iPhone/iPad、TestFlight 和 Production CloudKit 通过；
10. P0/P1 与文档未验收项归零，证据和提交可追溯。

---

## 10. 给 Grok 4.6 的执行指令

```text
请按 Documentation/IPHONE_IPAD_ACCEPTANCE_REMEDIATION_GUIDE.md 执行返工，并以
Documentation/IPHONE_IPAD_IMPLEMENTATION_PLAN.md 作为详细架构和测试合同。

先完成 Gate 0，保护当前未提交工作，修复两个 CloudKit P0，并清理第五入口文档残留。
Gate 0 的测试和提交证据完整后，再建立一个同时支持 iPhone/iPad 的 iOS target。

每个 Gate 开始前报告 Git 状态、修改范围、依赖图、风险和验收命令；完成后报告平台化测试结果、
退出码、证据目录、commit SHA 和遗留项。不要复制业务代码，不要创建第二套 schema、CloudKit
container、App Group、仓库或 App Store 产品记录。不要把 macOS 测试、iOS 模拟器、真机和
Production CloudKit 混成一个“已完成”结论。未经用户明确授权，不推送、不合并、不清理工作区。
```
