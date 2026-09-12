# 知行仓库协作规则

## 分支与发布宪法

`Documentation/BRANCH_AND_RELEASE_CONSTITUTION.md` 是本仓库分支命名、合并、发布、热修复与分支清理的唯一规范。开始涉及 Git 分支、tag、GitHub Release 或发布产物的工作前，必须先遵循该宪法；与其他仓库惯例冲突时，以本宪法为准。

## 大改动与版本更新

凡是影响产品体验、数据模型、同步、平台能力、图标或版本号的改动，完成后默认执行：

```bash
Source/Scripts/release-local.sh
```

除非用户明确要求跳过，否则不要停在源码修改或单元测试通过。完整流程必须依次完成 macOS 测试、iOS Simulator 编译、Universal DMG 打包、`Releases/<版本>/` 归档与 SHA-256、替换安装 `/Applications/知行.app`、签名与版本验证。

只改文档、测试或与 App 无关的文件时，不触发完整发布。

## 清理边界

每轮发布前后运行 `Source/Scripts/cleanup-release-residue.sh`。它只清理可再生的 DerivedData、旧的 `Source/dist` DMG、Finder/编辑器临时文件，以及经 bundle ID 确认的旧“知行.app.backup-*”安装备份；发布后保留当前 DMG。

本轮自行创建的草稿、截图、临时分析和中间决策文件，在交付前删除。不要删除用户数据、偏好设置、数据库、正式文档、发布说明或 `Releases/` 下的历史版本归档。无法确认归属的文件先保留。
