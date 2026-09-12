# 知行 1.0.8

## 单实例与误启动 DerivedData

- 验收时曾同时出现深色与浅色两套「倒数展示」窗口，以及两枚相同的日历 + 8 菜单栏图标。只读盘点确认这不是两份正式安装包，而是两个同名进程：正式源 `/Applications/知行.app/Contents/MacOS/CalendarCountdown`（当时 PID 38384），以及 Xcode DerivedData Release 产物 `/Users/hashxjhuang/Library/Developer/Xcode/DerivedData/CalendarCountdown-buvinsbkcwybrweyhjwzbkzpxdqh/Build/Products/Release/CalendarCountdown.app/Contents/MacOS/CalendarCountdown`（当时 PID 40394）。
- 根因：发布或视觉验证用 `open -b` 按 Bundle ID 启动时，Launch Services 可能打开刚编过的 DerivedData 副本；该副本未退出，于是和第二套 NSStatusItem、第二扇窗口并存。用户数据目录未复制、也不应删除。
- 运行时单实例守卫：同一产品只能有一个持有者。`/Applications/知行.app` 优先；DerivedData 或第二实例会唤起主实例并立即退出，退出前不会再注册菜单栏项。历史 Bundle ID `com.hashxjhuang.CalendarCountdown` 同样纳入守卫；未知 Bundle ID 不会被当作本产品处理。
- 安装脚本不再 `killall`，也不再 `open -b`。替换前后只按 Bundle ID 与已验证的可执行路径结束本产品实例（含已知 DerivedData 路径），然后只打开 `/Applications/知行.app`，并检查此时只有一个主进程。无法确认身份的进程会保留并报告。

## 倒数选择恢复

- 本地 `countdown_selections` 与 SQLite 中的选择没有丢（验收时 25 条，tracked-events 23 条）。空列表是 EventKit 宽窗口截断，以及精确事件把去年 `occurrenceDate` 当成匹配条件，导致年度/重复事件对不上。
- 启动、刷新和权限恢复后，会按年切片查询 EventKit，并用日历项/外部稳定标识（日历 identifier 漂移时回退到日历标题）把已有选择重新匹配为展示中的倒数。无匹配时给出说明性空态，不清空选择、不自动重导入。

## 保留的 1.0.7 能力

- 三个独立菜单栏项、单色水位球/圆环、使命编辑器优化、日历授权恢复流程仍然有效。

## 验证边界

- macOS App、Widget、CLI、Core 与 Persistence 在本机完成构建和单元测试；iPhone/iPad 与移动 Widget 完成模拟器编译验证。
- 本发行包为 ad-hoc 本机签名，不等同于 Developer ID 签名、Apple 公证或真实 CloudKit 跨设备验收。
