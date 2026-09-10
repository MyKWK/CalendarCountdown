# iPhone / iPad 对外状态口径

准确口径：

**macOS 应用与共享领域/SQLite 同步底座已在本分支落地；iPhone/iPad 的 Xcode target、Info.plist、entitlements、四模块 UI、Widget 和测试 target 已写入工程。iPhone/iPad Simulator、双模拟器 CloudKit、真机、TestFlight、Production CloudKit 尚未在本环境验收。**

不要宣称「三端代码已经完成并验收通过」。

不要把本机未提交的 GRDB 2.0 工作树（48 Core + 26 Persistence）与本 Git 分支混为一谈。GitHub `grok/v2-p0-cloudkit-projection-broker` 从 `02af78a` 的 1.x macOS 工程起步，用 sqlite3 重建了可编译的共享底座和 iOS target。

| 项 | 本分支 |
|---|---|
| iOS App / Widget / Test / UITest target | 存在 |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` |
| iPhone TabView / iPad 三列 | 源码存在 |
| iOS Simulator 构建 | 未在 Linux 云环境执行 |
| 真机 / TestFlight | 未执行 |
