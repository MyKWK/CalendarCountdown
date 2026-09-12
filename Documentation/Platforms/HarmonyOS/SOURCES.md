# 官方资料索引与时效规则

> 访问与核对日期：2026-09-12。链接中的产品版本、开放资格、地区与 API 内容会变化；H1/H2 实施前必须重新打开所有“需实时核验”项。

| 主题 | 官方来源 | 本知识库采用的结论 | 时效 |
|---|---|---|---|
| HarmonyOS 应用开发总览 | [应用开发导读](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/application-dev-guide) | DevEco Studio 是推荐 IDE；文档覆盖入门、Kit 开放能力、工具和 API 参考 | 需实时核验 |
| ArkTS / ArkUI / DevEco 入门 | [HarmonyOS 开发入门](https://developer.huawei.com/consumer/cn/develop-novice-guide/) | ArkTS 是优选主力应用语言，ArkUI 是声明式 UI；模拟器/预览器通常免签名，真机需签名 | 需实时核验 |
| 产品开发路径 | [设计与开发 HarmonyOS NEXT 应用](https://developer.huawei.com/consumer/cn/app/planning) | DevEco Studio 提供工程、构建、调测与模拟仿真；模板和语言支持随版本变化 | 需实时核验 |
| 仓颉首页 | [仓颉 - 华为开发者联盟](https://developer.huawei.com/consumer/cn/cangjie) | 仓颉面向 HarmonyOS 应用开发，官方提供文档、工具和体验入口 | 需实时核验 |
| 仓颉 HarmonyOS 入门 | [仓颉官方文档：HarmonyOS 应用开发入门指导](https://docs.cangjie-lang.cn/docs/0.53.18/guide/source_zh_cn/%E4%BB%93%E9%A2%89%E9%B8%BF%E8%92%99%E5%BA%94%E7%94%A8%E5%BC%80%E5%8F%91%E5%85%A5%E9%97%A8%E6%8C%87%E5%8D%97.html) | 公测、插件、SDK 默认路径、`[Cangjie] Empty Ability`/Hybrid、Phone 模拟器步骤；文中 5.0/Beta2 为示例版本 | **高风险，实施前逐条核验** |
| 仓颉 IDE 插件能力 | [仓颉官方文档：IDE 插件](https://docs.cangjie-lang.cn/docs/0.53.18/white_paper/source_zh_cn/cj-wp-ideplug.html) | 说明 DevEco Studio 中的仓颉工程管理、构建、HAP 推送及调试能力；仍须按插件版本实测 | 高风险 |
| DevEco GUI 模拟器 | [使用模拟器](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/ide-emulator-use-V14) | 模拟器用于无真机开发、调试、网络/文件/工具栏等场景 | 需实时核验 |
| Emulator CLI | [通过命令行使用模拟器](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-emulator-command-line) | CLI 随 DevEco/Command Line Tools；可管理镜像与实例并做场景模拟；命令参数随版本变化 | **高风险，实施前逐条核验** |
| 数据存储选择 | [数据存储方案如何选择](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-local-database-management-38) | Preferences、键值库与关系库有不同用途；结构化领域记录优先评估关系库 | 需实时核验 |
| 数据管理概念 | [Application Data Management](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V3/basic-data-mgmt-0000000000026071-V3) | 官方说明本地关系/ORM/轻量存储与跨设备数据能力；英文 V3 为概念参考，不能替代当前 API 文档 | 历史概念参考 |

## 使用规则

1. 优先使用 `developer.huawei.com` 与 `docs.cangjie-lang.cn` 的原始资料；社区贴、课程与第三方博客只能帮助定位问题，不能决定产品能力或 CI 命令。
2. 记录时必须带上访问日期、IDE/SDK/API/插件版本与运行环境。不要只记录“鸿蒙 5/6”这类模糊标签。
3. 若官方页面链接失效、跳转或需登录，在 `STATUS.md` 记录现象和新的官方入口，不用搜索结果摘要代替原始证据。
4. 涉及签名、商店、权限、云服务、日历、后台、数据安全的结论，必须既有当前官方规则，也有对应真机/控制台证据，才可对外宣称可用。

