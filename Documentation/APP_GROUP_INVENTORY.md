# App Group 文件清单（2.0 基线）

路径：`~/Library/Group Containers/group.app.calendarcountdown.CalendarCountdown/CalendarCountdown/`

Mac、iPhone、iPad 共用同一 App Group identifier。App Group 只服务同一设备上的 App 与 Widget；跨设备复制走 CloudKit 记录，不复制数据库文件。

## SQLite 文件合同

`calendarcountdown-v2.sqlite` 是每台设备的离线权威副本。打开路径经 `AppDatabasePoolRegistry` intern：同一进程、同一标准化路径只保留一个 `DatabasePool`。Widget 不打开 SQLite。

`SQLiteFilePolicy` 在打开、WAL 准备和备份时标记：

| 路径 | iCloud/iTunes 备份 | iOS 文件保护 |
|---|---|---|
| `calendarcountdown-v2.sqlite` | 排除（`isExcludedFromBackup`） | `completeUntilFirstUserAuthentication` |
| `calendarcountdown-v2.sqlite-wal` | 排除 | 同上 |
| `calendarcountdown-v2.sqlite-shm` | 排除 | 同上 |
| 父目录与 `Backups/` | 排除 | 同上 |

macOS 没有 `URLFileProtection` 合同，只落实备份排除。不得把正在使用的 SQLite/WAL/SHM 放进 iCloud Drive 给多设备共用。

## 1.x JSON（遗留与镜像，不自动迁移为任务）

| 文件 | 角色 | CloudKit |
|---|---|---|
| `managed-events.json` | 本工具创建的倒数/生日规则索引；打开共享库时可一次性导入 SQLite | 不同步文件；对应记录为 `CDManagedEvent` |
| `countdown-selections.json` | 倒数选择镜像 | 不同步文件；对应记录为 `CDCountdownSelection` |
| `display-preferences.json` | 置顶与类别显隐镜像 | 置顶进 `CDCountdownPreferences`；隐藏日历仅本机 |
| `tracked-events.json` | 当前可见追踪清单（schemaVersion 1），供导出与 Widget | 不同步文件 |
| `widget-snapshot.json` | 倒数小组件只读快照 | 不同步 |

权威存储是 SQLite 表 `managed_events`、`countdown_selections`、`countdown_preferences`、`countdown_hidden_calendars`。JSON 由 App 在 `mirrorsLegacyJSON` 打开时回写，供 Widget 与 1.x 导出路径使用。

## 2.0 任务 / 使命 / 打卡 / 倒数

| 文件 | 角色 | CloudKit |
|---|---|---|
| `calendarcountdown-v2.sqlite` | 本机权威 SQLite（WAL）：任务、使命、习惯、倒数规则与追踪意图 | 不同步文件本身；同步其中的逻辑 record |
| `calendarcountdown-v2.sqlite-wal` | WAL | 不同步 |
| `calendarcountdown-v2.sqlite-shm` | shared memory | 不同步 |
| `Backups/` | migration 前一致性备份 | 不同步 |
| `widget-snapshot-v2.json` | 任务/使命/打卡小组件快照（后续） | 不同步 |
| `broker.sock` | CLI/MCP 本地 Broker（macOS） | 不同步 |

Widget 只读 JSON 快照，不打开 SQLite。
