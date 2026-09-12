# 知行分支与发布宪法

> 状态：生效。除非本宪法明确允许，任何人或自动化均不得绕过本规则。
>
> 适用范围：`CalendarCountdown` 仓库及其 macOS、iOS/iPadOS、HarmonyOS 和命令行 Target。

## 1. 目标

让每个提交、可安装的本机版本和 GitHub 上可下载的正式版本都有唯一、可追溯的来源：

```text
feature/* | platform/* | fix/* | hotfix/*
                    ↓
                 master
     本机完整验收与 /Applications/知行.app
                    ↓
             release/<版本> + v<版本> tag
          GitHub 完整交付物与发布说明
```

## 2. 分支职责

| 分支 | 作用 | 允许的内容 | 禁止事项 |
| --- | --- | --- | --- |
| `feature/<主题>`、`platform/<平台>`、`fix/<主题>` | 独立开发与验证 | 单一目标的实现、测试、文档 | 直接作为正式安装或公开发布来源 |
| `master` | 本地集成与最后一道验收屏障 | 已完成开发目标的整合、版本准备、发布记录 | 未通过完整发布流程即声称可交付 |
| `release/<主版本>.<次版本>.<补丁版本>` | 对外冻结的正式交付线 | 已从验收通过的 `master` 切出的发布提交；仅发布阻断修复与发布记录 | 普通功能、历史重写、覆盖既有发布物 |
| `hotfix/<版本>-<主题>` | 已发布版本的紧急修复 | 单一、可验证的发布阻断修复 | 混入普通开发；修复后遗漏回合 `master` |

所有开发分支从当时最新的 `master` 建立；合并到 `master` 前必须说明目标、影响 Target、已完成的验证和未验证的边界。

## 3. `master` 的验收规则

`master` 是这台 Mac 上 `/Applications/知行.app` 的唯一源码来源。凡是影响产品体验、数据模型、同步、平台能力、图标或版本号的变更，在合并至 `master` 后必须运行：

```bash
Source/Scripts/release-local.sh
```

该流程的通过证据至少包括：macOS 测试、iOS Simulator 编译、Universal DMG、`Releases/<版本>/` 中的归档与 SHA-256、`/Applications/知行.app` 替换、签名与版本/架构校验。

这只证明本地 macOS 安装与脚本覆盖的 Target；不自动证明真机、CloudKit 跨设备、Developer ID、公证或其他平台商店审核。未覆盖的证据必须明确写在发布说明中。

完整流程通过且工作树干净后，`master` 必须推送至 `origin/master`。远端 `master` 不是公开下载页，但必须是可恢复、可审查的已验收历史。

## 4. 正式发布规则

1. 从已完成第 3 节验收的 `master` 创建 `release/<版本>`；该分支起点必须记录在发布说明中。
2. 在 `release/<版本>` 上复核版本号、DMG 名称、`Releases/<版本>/SHA256SUMS` 和发布说明。若需要改动，重新执行完整发布流程。
3. 推送该 release 分支，并在同一已验证提交创建不可移动的带注释标签 `v<版本>`。
4. GitHub Release 只能从 `v<版本>` 创建，附件至少包括对应 Universal DMG、`SHA256SUMS` 和发布说明；附件校验值必须与仓库归档一致。
5. 不覆盖、不删除已公开的 tag、GitHub Release 或历史 DMG。发现问题时递增版本号，走 `hotfix/*` 或下一版发布。

`release/*` 应在 GitHub 受保护：禁止 force-push 和删除；合并/推送仅限项目维护者。`master` 同样禁止 force-push；自动化检查可在启用后成为合并门槛，但不能替代本机安装证据。

## 5. 分支生命周期与清理

开发分支在合入 `master`、其验证证据已记录且没有有效 worktree 占用后，应删除本地与远端分支。未合并分支、被 worktree 占用的分支、`master`、`release/*`、`hotfix/*`、以及所有 `v*` tag 均不得以“清理”为由删除。

清理前必须先获取远端引用并验证候选分支是 `master` 的祖先；清理不得使用 force-push、不得删除 GitHub Release、tag、`Releases/` 历史归档、用户数据或未追踪文件。失效的临时 worktree 仅可用 `git worktree prune` 清除其元数据，不得猜测或删除其原始目录。
