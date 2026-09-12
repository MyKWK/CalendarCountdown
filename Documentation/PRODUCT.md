# 日历倒数产品合同

## 产品定位

“日历倒数”是 Apple 日历的增强客户端。Mac、iPhone、iPad 是**同一个 App**，macOS 为主力与先发端。Apple 日历是事件和分类的唯一可见来源；本工具负责选择哪些事件参与倒数、计算农历规则、管理任务/使命/打卡，并提供菜单栏（macOS）、小组件和 AI 可调用的 CLI（macOS）。

## 平台

- 三端共用同一套领域模型、SQLite schema、CloudKit container 和 App Group。
- iPhone/iPad 是同一产品的 iOS target，不另开仓库、不另开 App Store 应用记录。
- 一级模块与当前 macOS 侧栏一致：**倒数日、任务清单、使命清单、打卡**。
- macOS 专属：菜单栏、本地 Broker、CLI。不把这些能力伪装成 iOS 必备。

## MVP 范围

- 读取用户授权的 Apple 日历事件。
- 按 Apple 日历的账户来源与日历分类展示事件，不在软件内部重复建立分类。
- 用户逐个选择参与倒数的事件；选择一个日历不等于自动选择该日历中的全部事件。
- 颜色直接沿用事件所属 Apple 日历的颜色。
- 写入时必须明确选择目标 Apple 日历；默认只编辑或删除本工具创建并带稳定标识的事件。
- 支持一次性事件、公历年度生日、农历年度生日和提前提醒。
- 农历年度生日由本工具保存规则，并滚动生成未来十年的公历事件实例。
- 菜单栏展示最近一个事件，点击后展示最近十个事件。
- WidgetKit 小组件展示最近事件，并按本地自然日计算倒数。
- App、菜单栏与 WidgetKit 小组件跟随系统语言，支持简体中文、英语、日语、韩语、西班牙语和俄语。
- CLI 提供稳定 JSON 输出、明确退出码、预演导入和诊断能力。
- 自动维护当前可见追踪项的版本化 `tracked-events.json`，并支持在 App 中一键导出。

## Apple 日历映射

Apple 日历的账户来源和日历分类由系统管理。本工具读取现有分类；用户可以在 Apple 日历中建立“生日”等日历，然后将生日事件写入该分类。

本工具自己的记录通过 `calendarcountdown://event/<UUID>` URL 标识。公历生日直接写入用户选择的“生日”日历；农历生日在同一日历中生成带年份参数的独立实例。

倒数选择有三种语义：

- `exactEvent`：仅选择某一个确定的事件实例。
- `annualTitle`：在指定 Apple 日历内，持续选择同名的下一次事件，适合订阅日历中的“元旦”。
- `managedRecord`：选择本工具创建的一次性或重复事件记录，适合导入生日和单次倒数。

## 追踪清单与倒数同步

Apple 日历仍是事件内容的唯一事实源。`tracked-events.json` 不是第二套日历数据库，只是当前“倒数展示”中可见追踪项的可携带索引。

本工具管理的倒数规则、追踪选择和置顶以每台设备的 SQLite 为离线副本，经 CloudKit private database 做记录级复制（`CDManagedEvent`、`CDCountdownSelection`、`CDCountdownPreferences`）。不上传 EventKit `eventIdentifier` / `calendarIdentifier`，也不把 Apple 日历事件正文复制进 CloudKit。隐藏的日历类别仅本机保存。

文档使用 `schemaVersion: 1`，每个事件包含：

- 稳定的追踪 UUID、标题和事件类型（生日、纪念日、单次重要日或其他）。
- `date.startYear`，以及月、日和 `calendarSystem`（`gregorian` / `lunar`）。农历另带闰月标记、闰月策略和无效日期策略。
- 循环频率，以及循环采用的历法。
- 下一次发生日期、全天/时间/时区。
- Apple 日历来源、分类、颜色和可用于重新关联的标识。
- 追踪方式、开始追踪时间和是否置顶。

完整示例见 [tracked-events.example.json](tracked-events.example.json)。App 的“导出追踪清单”不需要改写 Apple 日历；CLI 可用 `calcount tracking list`、`tracking refresh` 和 `tracking export --output FILE.json`。

## 倒数规则

- 以当前系统时区的自然日为边界。
- 今天发生的事件显示“今天”，明天显示“1 天”。
- 已过期事件默认不进入“最近事件”。
- 全天事件和指定时间事件在 MVP 中都按自然日倒数。

## 农历规则

- 使用 Foundation 中国农历计算对应公历日期。
- 默认不匹配闰月；可显式选择只匹配闰月或普通月与闰月都匹配。
- 当指定农历三十而当年月仅有二十九天时，默认回退到该月最后一天，也可选择严格跳过。
- 农历生成事件属于本工具管理数据；修改生日规则应通过 App 或 CLI 完成。

## CLI 安全合同

- `list` 按 Apple 日历原生分类返回事件；写操作必须指定目标日历。
- `import --dry-run` 只校验和预览，不写入 EventKit。
- JSON 模式不输出非 JSON 提示文字。
- 事件 ID 使用 UUID，不把标题当作唯一键。
- 导入中的 `externalId` 用于幂等去重。

## 2.0 任务、使命与打卡

2.0 在倒数之外增加独立的任务系统。倒数事件不是任务；习惯不是使命。

- **任务**：可完成的事项，SQLite 是事实源；默认不投影到 Apple 提醒事项。
- **使命**：有边界、最终可完成的长期结果。进度 = 已完成工作量 ÷ 计划工作量；新增任务会稀释分母。无限循环不进入成果百分比，只显示持续性。
- **打卡**：关注一致性而非最终做完。统计只来自 SQLite CheckIn。
- **同步**：每台设备一份 SQLite；CloudKit 按记录复制（默认仅本机）。不得把正在使用的 SQLite 放到 iCloud Drive 给多设备共用。SQLite、WAL、SHM 与备份目录排除 iCloud 备份；iOS 使用 `completeUntilFirstUserAuthentication` 文件保护；进程内同一路径只保留一个 `DatabasePool`。
- **投影**：Apple 日历/提醒事项可重建，删除投影不得删除核心任务。

最低系统：macOS 15 为首发主力；iOS/iPadOS 18 为同一产品的移动端部署下限。schemaVersion 1 导入仍只解释为倒数事件。

## 非目标

- 不实现 CalDAV 服务器，也不复制 Apple 日历的分类体系。
- 不把 Apple 日历事件正文上传为第二套云端日历；CloudKit 只同步本工具自己的逻辑记录。
- 不承诺 Apple 日历对生成农历实例的直接编辑会反向改变农历规则。
- 不为 iPhone/iPad 做独立产品、独立仓库或独立 App Store 记录。
