# 知行 1.0.9

## 跨进程单实例锁

- 1.0.8 的单实例守卫只看 `NSWorkspace` 进程快照。两个实例同时启动时，都可能在对方进入 `runningApplications` 之前看到空列表，于是双方都成为持有者并各自注册菜单栏。
- 1.0.9 在初始化窗口和状态栏之前，先用 Application Support 下的 `CalendarCountdown/Runtime/single-instance.lock` 做跨进程原子占有（`O_CREAT|O_EXCL` + `flock`）。路径不依赖主题，也不依赖 DerivedData。
- 锁文件记录 PID；启动时检查进程是否仍存活。陈旧锁会安全回收。正常退出会释放。失败者只激活已有持有者并立即退出。
- `/Applications/知行.app` 仍优先于 DerivedData 与历史副本；两份正式安装同时启动时，先拿到锁的一方留下。

## 保留的 1.0.8 / 1.0.7 能力

- 倒数选择按年切片重匹配、空匹配不清空用户数据、安装脚本不 `killall` / 不 `open -b`，以及三个独立菜单栏项、单色水位球、使命编辑器和日历授权恢复仍然有效。

## 验证边界

- Core 测试覆盖两个并发 claim 仅一个成功，以及陈旧锁回收。
- 本地发布安装后检查 `/Applications/知行.app` 只有一个主进程。
- 本发行包为 ad-hoc 本机签名，不等同于 Developer ID 签名、Apple 公证或真实 CloudKit 跨设备验收。
