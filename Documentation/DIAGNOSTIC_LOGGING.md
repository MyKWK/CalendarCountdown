# CalendarCountdown 本地诊断日志

CalendarCountdown 使用结构化 JSONL 日志记录 App、`calcount`、Widget、SQLite、App Broker、Apple 日历/提醒事项投影和 CloudKit 同步的关键运行节点。

## 本地边界

- App 与 CLI：`~/Library/Application Support/CalendarCountdown/Diagnostics/`
- Widget：位于 Widget 自己的沙盒 `Application Support/CalendarCountdown/Diagnostics/`
- 日志目录不使用 App Group，也不位于 iCloud Drive；目录和文件同时设置 `isExcludedFromBackup`。
- CloudKit schema 和 outbox 中没有日志记录类型。多端之间只通过现有业务记录同步，日志正文不会上传到 CloudKit。
- 文件权限为 `0600`，仅当前 macOS 用户可读写。

## 保留与清理

- 每个组件每天一个文件：`calendarcountdown-<component>-YYYY-MM-DD.jsonl`。
- 仅保留当前日期和此前 29 个日历日（合计 30 天）；更早的日志文件会删除。
- App 启动时执行一次清理，运行期间每 24 小时执行一次；各进程写日志时也会最多每 24 小时做一次维护，因此 CLI 或 Widget 单独运行也不会绕过保留策略。

## 多端关联

每条日志都包含进程级 `sessionID` 和本机安装级 `installationID`。数据库打开后还会包含持久化的 `localDeviceID`。Broker 请求使用同一个 `correlationID` 贯穿 CLI、Broker 与命令路由；一次手动 CloudKit 同步会生成独立同步周期 ID。

收到 CloudKit 记录时，日志只记录来源 `remote_device_ids`、记录类型及 created/updated/conflicts/failed 等计数，不记录 `payloadJSON`、字段快照或业务正文。这样可以对照不同设备的本地日志排查“哪台设备在何时产生、发送和应用了变更”，同时不把日志本身变成同步数据。

## 隐私与脱敏

日志调用不得传入任务标题、日历事件标题、备注、命令参数正文或 CloudKit payload。日志核心还会对 token、secret、password、authorization、payload、params、body 等字段强制替换为 `<redacted>`，并识别正文中的 Bearer token。每个字段最多保留 2,048 个字符。

## 排查命令

```sh
calcount logs status
calcount logs list
calcount logs path
calcount logs cleanup
```

`logs status` 返回本地目录、30 天保留策略、是否为非 ubiquitous 本地目录、是否排除备份，以及现有文件名/大小/修改时间；`list` 和 `path` 分别提供精简的文件清单和目录结果。`logs cleanup` 立即执行一次相同的保留策略。

JSONL 可以用系统工具查看，例如：

```sh
jq -c 'select(.category == "sync")' ~/Library/Application\ Support/CalendarCountdown/Diagnostics/*.jsonl
```

如果需要同时观察 Widget 与 App 的实时摘要，可在 Console.app 中以 subsystem `app.calendarcountdown.CalendarCountdown` 过滤。统一日志只镜像事件名和已经脱敏的元数据；JSONL 文件仍是长期（最长 30 天）排查依据。
