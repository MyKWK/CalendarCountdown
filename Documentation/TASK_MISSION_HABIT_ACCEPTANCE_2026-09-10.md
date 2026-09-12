# CalendarCountdown 2.0 任务、使命、打卡验收报告

> 验收日期：2026-09-10
> 验收基线：`master` / `02af78a` 加当前未提交工作区
> 结论：**不通过，禁止按“三个模块已完成”发布或合并。**

## 1. 总结

当前交付已经建立了 Task、Mission、Habit、CheckIn 的领域模型、GRDB/SQLite v1 schema、部分循环与进度算法、基础 SwiftUI 页面、CLI 命令和一个最小 MCP stdio server。Debug 测试和 Release Universal 编译均能通过。

但产品最关键的三条主链路没有完成：

1. SQLite 没有通过 CloudKit/CKSyncEngine 跨设备同步；现有 `cloud` 只是手工导出和导入 JSON bundle。
2. Task/Habit/Mission 没有真正写入 Apple 日历或提醒事项；现有代码只计算 desired projection，生产代码没有执行投影或接收 Apple 完成状态。
3. CLI/MCP 没有经过 App Broker；CLI 和 MCP 直接打开 SQLite，旧 EventKit 命令仍由 CLI 自己申请权限。

因此，这次交付可以认定为“本地领域与持久化骨架基本成立”，不能认定为三个模块完成。

## 2. 已验证通过

- Debug：App、Widget、CLI 编译通过。
- XCTest：Core 42 项、Persistence/Service 10 项，共 52 项通过，0 失败。
- Release：App、Widget、CLI 的 `arm64 + x86_64` Universal build 通过。
- SQLite：临时数据库可创建、WAL/foreign keys/migration 可运行，`PRAGMA integrity_check` 返回 `ok`。
- 本地 Task：单次、固定计划循环、完成后循环的主要纯算法测试通过。
- 本地 Mission：工作量加权、动态分母稀释和无限循环排除的单元测试通过。
- 本地 Habit：binary/count/quantity 的打卡、撤销和部分统计测试通过。
- CLI：隔离目录内创建 Mission、Task、列出数据和 dry-run 可执行；dry-run 后 Task 行数仍为 0。
- MCP：`initialize` 和 `tools/list` 可返回基础 JSON-RPC 响应。
- `git diff --check` 通过。

以上通过项不包含真实 CloudKit、Apple Calendar/Reminders、签名、公证、安装包或多设备 E2E。

## 3. 阻断问题

### P0-1：CloudKit/CKSyncEngine 完全未实现

证据：

- `Source/Persistence/CloudSync.swift` 只依赖 Foundation/GRDB，没有 `import CloudKit`，也没有 CKContainer、CKDatabase、CKRecordZone 或 CKSyncEngine。
- `CloudSyncService.exportPending` 和 `apply` 只是本地 CloudBundle 文件交换。
- `Source/project.yml` 没有 CloudKit framework、iCloud container、remote notification 配置。
- App/CLI/Widget entitlements 没有 iCloud/CloudKit capability。
- `capabilities` 把 `cloudKitMode` 固定返回 `localOnly`。

影响：SQLite 无法跨设备同步；离线并发、账号切换、远端恢复、production schema 均不存在。

### P0-2：Apple Reminder/Event 投影没有生产连线

证据：

- `Workspace.desiredProjections()` 只生成期望投影数组。
- `ReminderRepository.apply()` 存在，但全仓库没有生产调用者。
- `ReminderRepository.nativeItems()` 和 `ProjectionReconciler.reverseActions()` 只在定义或纯函数测试中出现。
- 没有 EventKit change observer、投影 worker、projection binding 更新、删除/重建、错误重试或 Saga 执行器。
- 默认 `ProjectionSettings.projectTasks == false`，UI 没有启用开关；UI 创建 Task/Habit 时也使用默认 `projectionPolicy == none`。

影响：用户在 App 中创建的任务不会出现在提醒事项或 Apple 日历；在 Apple 侧完成也不会回写 SQLite。时间段任务没有 Reminder + Event 双投影。

### P0-3：永久删除无法形成可同步的 delete record

`TaskService.delete(permanent:)` 先物理删除 task_occurrences 和 task_series，再把 delete 放入 outbox；但 `CloudSyncApplicator.envelope` 导出 CDTaskSeries 时必须重新从 task_series 读取对象，记录已不存在便直接返回 nil。

已复现：

- 创建一个 Task 后永久删除；
- `cloud_outbox` 中仍有 3 行（Occurrence upsert、Series upsert、Series delete）；
- `calcount cloud export` 返回 `recordCount: 0`。

另外，`cloud export --ack` 会无条件 `DELETE FROM cloud_outbox`，可把这种未导出的删除意图永久丢弃。

影响：一旦接上同步，其他设备可能保留或复活已删除任务，且本机可能错误地认为 outbox 已确认。

### P0-4：App Broker 不存在，权限主体和写入进程未统一

证据：

- 代码只有 `brokerSocketURL` 路径常量，没有 Unix socket listener/client、鉴权 token、App 唤起或超时处理。
- CLI 的 Task/Mission/Habit 命令直接调用 `Workspace.shared()` 打开 SQLite。
- MCP server 同样直接调用 `Workspace.shared()`。
- 旧日历命令仍直接创建 CLI 自己的 `EventKitRepository`。

影响：App、CLI、MCP 并非单一写入主体；CLI 的 TCC 权限仍可能与 App 分离，无法满足“App 已授权后 CLI/AI 无需另行授权”的设计合同。

## 4. 高优先级缺口

### P1-1：MCP 不能完整管理三个模块

当前只有 8 个工具：Task list/complete、Mission list/progress、Habit list/checkin、system capabilities/doctor。缺少至少：

- Task create/get/update/reopen/skip/archive/delete；
- Mission create/get/update/complete/add-task/remove-task；
- Habit create/get/update/undo/backfill/archive/delete/stats；
- 投影预演/执行/修复；
- Cloud sync/status/conflict；
- 统一 dry-run、idempotency、if-revision。

这不满足“所有模块允许 AI 助手操作”。MCP 工具错误也会抛出到整个 server，而不是返回规范 JSON-RPC error。

### P1-2：GUI 仅为骨架，无法完成设计中的主要配置和维护

Task GUI 只支持新建、完成、重开、跳过。循环选择只有“不循环/每天/每周”，每周被硬编码为周一、三、五；没有完成后循环、次数结束、日期结束、间隔、月末规则、提醒、优先级、投影策略、系列编辑范围、归档/删除和详情编辑。

Habit GUI 只支持标题、类型、目标和单位，实际固定使用 daily 默认规则；没有选定星期、每周/月 N 次、提醒时间、补打、撤销、休息/跳过、编辑或投影设置。

Mission GUI 只有新建、进度卡片和 100% 后完成；没有编辑、暂停、归档、目标日期、颜色图标、任务管理和完整进度解释页面。

### P1-3：Markdown 只保存，不解析展示

UI 只有名为“Markdown 描述”的 TextField。App 中没有 Markdown renderer、预览、分栏编辑或详情展示；任务行和使命卡片也不显示解析后的正文。

### P1-4：Widget 没有 Task/Mission/Habit 配置

虽然 Core 新增了 `WidgetSnapshotV2`，现有 Widget 仍读取旧 `WidgetSnapshot`，只渲染“最近倒数”。没有今日任务、使命进度、今日习惯三个 configuration，也没有快速打卡/完成。

### P1-5：Task update 合同没有服务和接口实现

Core 定义了 `PatchTaskCommand`，但 TaskService 没有 update/patch，CLI、MCP、GUI 也没有任务编辑命令。循环规则“仅此实例/未来实例/整个系列”的设计无法执行。

### P1-6：pending_operations 只写不消费

Task 创建或状态变化会插入 `pending_operations(stage = projection)`，但仓库没有完成、重试或清理这些 operation 的 worker。该表会持续积累，同时造成“已有 Saga”的假象。

### P1-7：Cloud merge 不是可验收的三方合并

当前 bundle applicator 没有持久化真实 common ancestor，而是从 client/server 较旧的 HLC 临时推导 ancestor。它无法替代 CKRecord changeTag、serverRecordChanged 和持久化 ancestor 的真实三方合并。现有测试只覆盖手工构造的纯函数输入。

## 5. 中优先级问题

### P2-1：CLI 未严格拒绝未知参数

`Arguments` 只提供 contains/firstIndex 查询，没有已消费参数或允许列表校验。实测 `calcount capabilities --bogus` 退出码为 0，且输出正常成功包。

### P2-2：capabilities/doctor 信息不可信或不完整

- `capabilities.cloudKitMode` 被硬编码为 `localOnly`，没有读取数据库模式或账号状态。
- MCP `system.doctor` 只执行 SQLite integrity，不报告 CloudKit account/zone/outbox/lastSync、EventKit 两类权限、投影漂移和 pending Saga。

### P2-3：交付不可追溯

当前 `master` 与 `origin/master` 都停在 `02af78a`，Grok 的交付是 21 个 modified 路径和 16 个 untracked 路径，没有独立 commit、branch 或 tag。无法准确区分作者改动，也无法进行可靠回退和 diff review。

### P2-4：设计图纸状态没有随实现更新

设计图纸顶部仍标注“实施中”，实现清单中 118 个 checkbox 全部未勾选。需要由实现者逐项附证据更新，不能仅口头宣布完成。

## 6. 本次验收顺手修复

仅修复了不改变产品语义的小问题：

1. 给 `Documentation/examples/v2/habit.create.example.json` 增加必填的 `reminderTimes: []`。修复前该仓库示例执行 `calcount habits create` 会报“数据丢失”；修复后隔离 CLI 创建成功。
2. 新增 `DomainCommandExampleTests.testV2CommandExamplesDecode`，防止三个公开 JSON 示例再次与 Codable 合同漂移。
3. 将 Persistence 测试中的未修改局部变量从 `var` 改为 `let`，清除编译警告。

修复后全量测试为 52 项通过。

## 7. 重新实施顺序

1. 先把当前工作保存为独立交付 commit/branch，建立可追溯基线。
2. 修正删除/tombstone/outbox/ack 语义，并补删除传播回归测试。
3. 真正实现 CloudKit private database + custom zone + CKSyncEngine + state serialization + account change + production schema。
4. 实现 App 内 projection worker、Reminder/Event CRUD、binding、反向完成、EventKit observer、repair 和可恢复 Saga。
5. 实现 Unix domain socket Broker；CLI/MCP 只调用 App Application Service，不直接开数据库或 EventKit。
6. 补齐 Task/Mission/Habit 的完整 service、CLI、MCP 和 GUI 操作面，再实现 Markdown 预览和 V2 Widgets。
7. 加入 CLI golden/unknown-flag 测试、MCP contract 测试、EventKit mock/integration、CloudKit 集成、UI、性能、备份恢复和迁移测试。
8. 最后进行真实双设备 CloudKit 收敛、Apple 日历/提醒事项双向动作、签名、公证、DMG 和 PATH 安装验收。

## 8. 重新验收门槛

| 验收层 | 当前结果 | 重新验收要求 |
|---|---|---|
| 源码/领域 | 部分通过 | 完整服务与接口面，设计 checklist 有证据 |
| Debug/测试 | 通过 | 保持全绿并新增集成测试 |
| Release Universal | 通过（未签名） | 保持 Universal，补签名/公证 |
| SQLite | 本地部分通过 | 重启、迁移失败恢复、备份恢复、删除传播通过 |
| CloudKit | 失败 | 两台真实设备离线并发后收敛 |
| Apple 投影 | 失败 | Reminder/Event 创建、更新、完成、删除、重建 E2E |
| Task 产品 | 部分通过 | 两类任务、两种循环、结束规则、编辑范围、Markdown 全通过 |
| Mission 产品 | 部分通过 | 稀释、解释器、状态、任务管理和 UI 全通过 |
| Habit 产品 | 部分通过 | 计划、提醒、补打、撤销、统计、投影全通过 |
| CLI | 部分通过 | 严格参数、完整 CRUD、Broker、权限一致性通过 |
| MCP/AI | 失败 | AI 真实完成创建→查询→完成/打卡→进度变化 |
| 发布 | 失败 | 可追溯 commit、production schema、签名、公证、DMG 通过 |

## 9. 本次使用的主要命令

```bash
xcodebuild -project Source/CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project Source/CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO build

git diff --check
```

所有 CLI 写入冒烟均使用隔离的临时 HOME/CFFIXED_USER_HOME 和临时 SQLite；本次验收没有向用户真实 Calendar/Reminders 写入或删除数据。
