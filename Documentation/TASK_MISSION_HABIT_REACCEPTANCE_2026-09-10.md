# Task / Mission / Habit 二次验收报告（返工后复验）

> 日期：2026-09-10
> 分支：`grok/v2-p0-cloudkit-projection-broker`
> 基线提交：`02af78a`；本轮改动仍未提交
> 验收边界：源码调用链、隔离 SQLite/CLI/MCP、Debug 单测、无签名 Universal Release 构建。不读取或写入真实 Apple 日历/提醒事项，不连接真实 iCloud。

## 结论

**本轮返工显著推进，但仍不通过发布验收。**

四项 P0 中，HabitPeriod outbox 已通过本地闭环验证；三类系统投影的领域分发、账号 profile 和持久 inbox 都已写入生产代码。但两条实际运行的 CloudKit/Broker 调用链仍会绕开返工保证：

1. `syncNow()` 在 fetched 应用失败后仍无条件覆盖 `lastFetchAt`；
2. App 已运行、Broker 尚未创建 CloudKit engine 时，CLI/MCP 首次执行 `cloud mode iCloud` 会创建一个**没有 `CloudProfileSession`** 的 engine，因而绕过账号 profile 隔离。

因此，当前准确的产品口径是：**知行 / PlanAct 的本地任务、使命、习惯核心和多数同步基础设施已实现；CloudKit 多账号安全与失败恢复仍有 P0 代码缺口，不能称为可发布的跨端同步。**

## 状态口径

| 状态 | 含义 |
|---|---|
| 已实现、已本地验证 | 已有生产代码，并由单测、隔离数据库或 CLI 验证。|
| 已实现、待真实验证 | 生产调用链已具备；仍需真实 Apple/iCloud/签名安装环境。|
| 部分实现或有缺陷 | 基础代码存在，但一条可到达的产品路径违反合同。先修代码，再做真实验证。|

## 本轮复验通过

- `xcodebuild test`（Debug、macOS、`CODE_SIGNING_ALLOWED=NO`）：**67/67** 通过（Core 43 + Persistence 24）。
- `git diff --check` 通过。
- Release 无签名构建成功；App 与 `calcount` 均为 `arm64 + x86_64` Universal Mach-O。
- 隔离 HOME 的 CLI direct 验证通过：`projections set --tasks true --habits false --missions true` 写入一致设置；非法 `--transport`、缺少 value flag 均被拒绝。
- 隔离 HOME 的 MCP stdio 验证通过：坏 JSON 返回 JSON-RPC parse error；`notifications/initialized` 不返回响应；`tools/list` 能列出工具及已覆盖工具的字段 schema。
- `HabitPeriod` skip 两库 round-trip、坏 payload 入 inbox 且不推进 fetch 时间、父子记录乱序 deferred/replay、profile A/B 隔离、投影失败保留 pending saga 均有单测。

这些结果只说明编译、本地持久化和被覆盖的调用路径正确；不等于真实 CloudKit/EventKit/Widget 发布验收。

## P0 逐项复验

| 项目 | 实现状态 | 本地证据 | 结论与下一步 |
|---|---|---|---|
| P0-1 账号 profile 隔离 | **部分实现或有缺陷** | `CloudProfileSession` 会将 A/B 数据库切到 `Profiles/<hash>/`，首次启用可提升本地库，`testCloudProfileIsolationDoesNotMixAccounts` 通过。 | GUI 创建的 engine 会注入 session；但 Broker 在 `cloud.set-mode` 时自行 `CloudKitSyncEngine(workspace:)`，未传 session。CLI/MCP 首次启用 iCloud 可绕过隔离。应让 Broker 委托 AppDelegate 创建 engine，或向 Broker 注入同一 session 和 workspace-change 回调；补 Broker 账户切换集成测试。 |
| P0-2 fetched 持久 inbox | **部分实现或有缺陷** | `cloud_inbox` 持久化、依赖重放、坏 payload 留存的 service 层测试均通过。 | `CloudKitSyncEngine.syncNow()` 在 `fetchChanges()` 后无条件写 `lastFetchAt=Date()`，会覆盖 `ingestFetched` 在失败时“不推进”的决定。删除该无条件写入；时间只能在成功应用或空批次时前进。补 engine 层失败 fetch 回归。 |
| P0-3 HabitPeriod outbox | **已实现、已本地验证** | check-in、undo、skip 都 enqueue `CDHabitPeriod`；effect 返回的 record name 是 period identity；两库 skip round-trip 通过。 | 纳入真实双设备的 skip/undo/历史 target 回归即可。 |
| P0-4 三类投影闭环 | **已实现、待真实验证** | GUI 有任务/习惯/使命三个投影开关；CLI `projections set` 已验证；reconciler 按 domainType 分发 Task、Habit、Mission，Habit 原生完成写 check-in 的内存测试通过。 | Mission reminder + 可选 target-date 全天 event 已生成，未引入 reminder list。仍缺真实 EventKit 权限、完成/重开、删除重建 E2E；Mission complete/reopen 还应增加持久层集成回归。 |

### 两个仍阻断发布的 P0 缺陷

#### P0-1：Broker 首次开启 iCloud 绕过 profile session

`AppBrokerServer.runSetCloudMode` 在 `cloudEngine == nil` 时直接构造 `CloudKitSyncEngine(workspace: workspace)`。它没有 `profileSession`，也没有把 profile 切换后的 Workspace 回传给 `WorkspaceModel` 和 Broker。用户从默认 CLI/MCP 路径执行 `calcount cloud mode iCloud` 时，恰好可进入此分支。

修复：由 AppDelegate 持有唯一 engine 工厂，Broker 只请求“启用同步”；或者 Broker 构造 engine 时注入同一个 `CloudProfileSession`、`onWorkspaceChanged` 和 GUI 刷新回调。禁止任何没有 session 的生产 engine 启动 iCloud 模式。

#### P0-2：失败 fetch 的 observability cursor 被 `syncNow` 覆盖

Service 层 `ingestFetched` 的“失败不推进”实现和测试本身正确；但 engine 在 fetch 返回后仍写入当前时间。这使状态页/诊断无法再表达“本批本地应用失败”，也为后续以该字段决定重试策略留下错误基础。

修复：`syncNow` 只记录 send 成功所需的信息；不要写 fetch 时间。由 `applyFetched`/`ingestFetched` 按成功、空批次、失败三种结果唯一管理 `lastFetchAt`，并在失败时暴露 inbox 数和错误。增加 fake/injectable CloudKit transport 测试，以 engine 层而非只测 service 层验证该合同。

## P1 与次要项

| 项目 | 状态 | 复验结论 |
|---|---|---|
| 投影失败精确保留 saga | 已实现、已本地验证 | 失败 applier 测试确认失败项不再把 pending 全部标 completed。仍需权限拒绝、删除失败和重启恢复测试。 |
| Widget V2 双写与 App Group | 已实现、待真实验证 | App Group entitlement 已加到 App/Widget；V2 快照写 App Support、共享容器和 Widget 容器。没有签名安装后的读取/刷新证据。 |
| CloudKit 应用后 GUI/投影刷新 | 已实现、待真实验证 | service 发通知，App 同时订阅通知和 engine callback 后 reload/reconcile。没有真实远端事件验证。 |
| APS/App Group 配置 | 已实现、待平台验证 | `aps-environment` 和 App Group 已在 entitlement。Release 构建仍会移除 macOS 不支持的 `remote-notification` background mode；不能据此承诺 App 未运行时推送唤醒。 |
| Broker doctor/capabilities | 已实现、已本地验证 | Router 支持 brokerListening；单测覆盖 `broker=true` / `brokerListening=true`。仍应做安装 App 后的 socket 自启动、并发和重连测试。 |
| MCP 协议 | 部分实现 | parse error、notification 无响应已实测；create、complete、skip、投影设置等有字段 schema。但 `tasks.update`、`missions.update/delete/add-task/remove-task`、`habits.get/update/undo/delete` 等仍退回 `{type: object}`。若 MCP 是正式 AI 接口，应补全所有写操作及删除确认参数的 schema。 |
| CLI 参数校验 | 已实现、已本地验证 | 缺值 flag 与非法 transport 已实测拒绝。 |
| Reminder 清空 due | 已实现、待适配器验证 | 代码已将无 due 的 desired 清为 `nil`；缺 EventKit adapter 级回归和真实提醒事项验证。 |

## 跨端架构口径增量复验

本次新增口径中，下列项目已由代码与 macOS 本地测试支持：

- Mac、iPhone、iPad 被定义为同一产品；当前工程仍只有 macOS targets，iOS target **尚未创建**，没有把移动端误报为已交付。
- 当前 `RootView` 的四个一级侧栏入口是倒数日、任务清单、使命清单、打卡；没有第五个 `SidebarItem.today`。
- 倒数同步使用 `CDManagedEvent`、`CDCountdownSelection`、`CDCountdownPreferences`。cloud payload 会剥离 `calendarIdentifier` 与 EventKit `eventIdentifier`；隐藏日历只留本地；两库 round-trip 测试覆盖了 ManagedEvent/Selection/Preferences 的核心边界。
- `AppDatabasePoolRegistry` 按标准化路径复用同一 `DatabasePool`；数据库、WAL/SHM、目录和备份目录会设置 `isExcludedFromBackup`。对应 persistence 测试已验证同一路径复用和数据库文件的备份排除。

仍须准确区分以下限制：

- `completeUntilFirstUserAuthentication` 是 `#if os(iOS)` 的已实现代码分支，但当前项目全为 `SDKROOT=macosx`，本轮 48 Core + 26 Persistence 测试只在 macOS 运行，**不能称为 iOS 运行时已验证**。iOS target 建立后应增加真机/模拟器的文件保护与 App Group container 测试。
- `TASK_MISSION_HABIT_BLUEPRINT.md` 的旧第 10.1 节仍画有“今天 / 任务 / 使命 / 打卡 / 倒数”的主导航；`IPHONE_IPAD_IMPLEMENTATION_PLAN.md` 也仍保留“今天”作为首个移动端功能段落。这与“只有四个一级入口”口径不一致。应由产品确认“今天”是否只作为任务清单内的筛选/摘要；确认后删除或改写这两处，不要让它重新演变为第五个 tab。
- 本节不解除前述 P0-1/P0-2 CloudKit 发布阻断项；倒数记录新增同步模型同样依赖这两条总同步路径正确后才能进入真实 iCloud 验收。

## 仍须真实环境验收（不是“未实现”）

- 两台 Mac、同一 iCloud 账号：首次同步、离线并发、冲突、tombstone 删除、网络恢复。
- 两个 iCloud 账号：在修复 P0-1 后验证 A → 登出 → B → A，不混数据也不串 outbox。
- CloudKit development schema 到 production schema 部署。
- Calendar/Reminders：授权、拒绝授权、可见性、完成/重开回写、重复任务、删除重建。
- 签名安装后的三类 Widget 读取与刷新。
- Developer ID 签名、公证、安装包、升级/回滚。
- 旧倒数 EventKit CLI 仍由 CLI 自身发起 TCC，尚未统一到 App Broker；这是已知待清项。

## 给 Grok 的返工顺序

1. 修 P0-1：统一 GUI、Broker、CLI/MCP 的 CloudKit engine 创建入口，并强制 profile session。
2. 修 P0-2：移除 `syncNow` 的无条件 fetch timestamp 覆盖，补 engine 级失败回归。
3. 补投影持久层测试（尤其 Mission complete/reopen）和 MCP 全量 schema。
4. 再进入真实双机 CloudKit 与 EventKit/Widget/签名验收。

在 1–2 完成并通过新的本地回归前，不建议打开真实 iCloud 同步开关。
