# 知行多端产品、仓库与分支治理

> 状态：已批准的开发治理基线，非实现完成声明  
> 建立日期：2026-09-12  
> 适用仓库：CalendarCountdown（产品名：知行 / PlanAct）

## 1. 产品组合

| 平台 | 产品角色 | 当前阶段 | 事实源与同步边界 | 不属于该端的能力 |
|---|---|---|---|---|
| macOS | 主力、先发端 | 正在开发 | 本机 SQLite 是离线副本；产品逻辑记录通过同步服务复制；Apple Calendar / Reminders 仍是系统投影 | 不要求把移动端所有 UI 原样搬进桌面端 |
| iOS / iPadOS | 次主力、同一个移动 App | 正在开发 | 与 macOS 共享产品合同、领域 UUID、schema 版本和同步合同；各端本机数据库独立 | 不运行 CLI、Broker、DMG 流程或菜单栏 |
| Android | 后续客户端 | 等待开发 | 共享中立 contracts、fixtures、迁移规则和同步 API；Android Calendar 是平台投影 | 不复用 Swift / GRDB / CloudKit 实现 |
| HarmonyOS | 后续客户端 | 等待开发 | 与 Android 同属非 Apple 客户端；本机 RDB + 中立同步服务；系统日历/提醒能力仅作可重建投影 | 不接入 CloudKit 私有数据库作为主同步方案；不复制 macOS CLI / 菜单栏 |

**产品不变式**：任务、使命、打卡、倒数追踪意图与本工具管理的规则使用稳定领域 UUID；系统日历、提醒事项及其 ID 都是本机 projection binding，不能作为跨端主键。任何平台都不得把另一个平台的日历全文当作云端事实源。

## 2. 仓库目录目标（现在只建文档，不移动源码）

当前 Swift/XcodeGen 工程继续保留在 `Source/`，直至 Apple 端 2.0 基线可追溯且可回归。未来新增内容采用并列目录，禁止把 ArkTS、仓颉、Kotlin 或其构建缓存混入 `Source/`：

```text
CalendarCountdown/
├── Source/                         # 现有 macOS / iOS / iPadOS Swift + XcodeGen
├── Documentation/
│   ├── PLATFORM_PORTFOLIO.md        # 本文：平台、目录、分支总约定
│   ├── Contracts/                   # 未来：JSON Schema、OpenAPI、版本迁移说明、golden fixtures
│   └── Platforms/
│       └── HarmonyOS/               # 本次建立的知识库（不含可执行应用）
├── harmonyos/                       # 未来：DevEco Studio 根工程，仅在实施阶段创建
│   ├── entry/                       # HAP entry Ability（建议 ArkTS）
│   ├── feature/                     # 可选功能 HAP
│   ├── shared/                      # HAR / HSP；只放 HarmonyOS 端可共享代码
│   ├── native/                      # 可选 C/C++；不是 Swift / Kotlin 的落点
│   └── test/                        # unit / UI / device test
├── android/                         # 未来：Android Gradle 根工程
├── contracts/                       # 未来：机器可读 schema 与 fixtures 的唯一落点
└── sync-server/                     # 未来：中立同步服务；独立部署与凭证边界
```

落地门槛：`harmonyos/`、`android/`、`contracts/`、`sync-server/` 任何一个目录在创建前，先由单独的架构提交确定其 build tool、最低 API、模块名、许可证和 CI 任务。不要以一个 Empty Ability 模板替代这项决策。

## 3. 分支与 worktree 规则

### 3.1 长期分支

| 类别 | 命名 | 用途 | 允许内容 |
|---|---|---|---|
| 当前 Apple 开发 | 现有团队分支，例如 `grok/ios-ipados` | macOS / iOS / iPadOS 的连续开发 | Apple 源码、测试、Apple 文档；不得夹带鸿蒙脚手架 |
| 平台设计 | `codex/harmonyos-foundation` | 本次资料库、目录与跨端合同设计 | 仅治理文档、架构图、官方资料索引 |
| HarmonyOS 初始化 | `codex/harmonyos-bootstrap` | DevEco 工程、CI smoke build、最小 ArkTS shell | 仅在环境验收完成后从已冻结基线创建 |
| HarmonyOS 功能 | `codex/harmonyos-<slice>` | 按领域切片（例如 `domain-store`、`countdown-read`） | 一个可验证切片，禁止和 Apple 大改混合 |
| Android 初始化/功能 | `codex/android-<slice>` | 同上 | 保持与 HarmonyOS 分支解耦 |

不要用一个永久 `harmonyos` 分支承担全部开发，也不要把开发分支直接合入 `main`/发布分支。每个分支以单平台、单层次（合同、数据、UI、投影、发布）为边界。

### 3.2 并发隔离

1. 现有 Apple 工作区有未提交内容时，跨端调研、文档或实验一律放入独立 worktree。
2. 新 worktree 从一个明确的已提交 SHA 建立，并在其 `Documentation/Platforms/HarmonyOS/STATUS.md` 记录基线 SHA、分支和创建目的。
3. 不在别的 worktree 中执行 `git clean`、重建 `Source/CalendarCountdown.xcodeproj`、发布脚本或依赖升级。
4. 仓颉 SDK、DevEco SDK、模拟器镜像、`oh_modules/`、`build/`、签名文件和日志只在本机工具目录或 `harmonyos/` 的忽略路径；绝不提交凭证、Profile、p12、设备序列号或用户数据库。
5. 合并平台文档不等于授权创建应用工程；合并 bootstrap 不等于 Android/HarmonyOS 功能完成。

## 4. 跨端合同优先顺序

先冻结这些与语言无关的资产，后写任何客户端功能：

1. `DomainRecord`：UUID、类型、创建/修改 HLC 或等价排序键、软删除 tombstone、schemaVersion。
2. 命令与错误合同：创建/编辑/完成/恢复/归档、幂等键、校验错误与冲突表示。
3. 同步 envelope：outbox/inbox、ack、删除、冲突合并、未知 schema 的拒绝策略。
4. projection contract：领域 UUID 到各端本机日历/提醒事项绑定；`needsDestinationSelection` 是明确状态，不能静默落到默认日历。
5. golden fixtures：同一输入在 Swift、Kotlin、ArkTS/仓颉实现中必须得到同一 JSON 结果。

Apple 的 `EventKit`、Android 的 `CalendarContract`、HarmonyOS 的系统能力及未来第三方账户接入，都只实现第 4 项的 adapter；它们不能改写第 1–3 项的语义。

## 5. 平台推进顺序与退出标准

| 阶段 | macOS / iOS 影响 | HarmonyOS 交付 | 退出标准 |
|---|---|---|---|
| H0 知识与账户 | 无 | 本知识库、官方链接、能力风险表 | 文档复核，且未创建可执行工程 |
| H1 工具链证据 | 无 | DevEco + API image + phone emulator + ArkTS Hello World | 可重复 build/run 截图或日志；不能称为产品移植 |
| H2 数据竖切 | 无 | RDB schema、fixture decoder、只读倒数/任务列表 | fixture 跨实现一致，离线重启仍正确 |
| H3 同步竖切 | 无 | 中立服务 outbox/inbox 和冲突用例 | 两模拟器或真机账户隔离验证；不以单机成功代替同步 |
| H4 系统投影 | 无 | 经授权的日历/提醒适配器 | 真机权限、拒绝路径、重装/重关联通过 |
| H5 发布候选 | 无 | 签名、隐私、性能、商店自检 | 真实设备与发布规则分别留存证据 |

本项目当前只达到 **H0**。这不是鸿蒙应用已构建、仓颉已可用、模拟器已安装或云同步已验证的证据。
