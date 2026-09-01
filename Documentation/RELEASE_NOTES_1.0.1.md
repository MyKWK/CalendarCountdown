# 日历倒数 1.0.1

## 修复

- 修复 Exchange 日历中的全天生日被保存为连续两天的问题。
- 新建全天事件现在根据日历来源选择正确的结束日期语义；iCloud/CalDAV 继续使用次日零点的半开区间，Exchange 使用当天 23:59:59。
- CLI 新增 `calcount repair all-day-events` 只读预览，以及带 `--apply` 的精确修复命令；只处理带有 `calendarcountdown://event/` 标识的本应用事件。
- 首次运行新版时，在新 App Group 尚无数据的前提下，自动复制旧版 App Group 中的事件记录、倒数选择、展示偏好和快照。

## 验证

- 新增单日全天边界及夏令时回归测试。
- 在 Exchange“生日”日历完成真实写入、回读和清理验证。
