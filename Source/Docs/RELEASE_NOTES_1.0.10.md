# 知行 1.0.10

## 主线整合版

- 汇入固定科技风主题、使命独立色彩、改进后的使命编辑器及状态栏展示能力。
- 汇入 iPhone、iPad、跨平台 Swift Core 与 HarmonyOS 基础设施，保持当前 `Platforms/iOS` 架构为唯一移动端实现。
- 本版以单实例锁和安全安装流程防止 DerivedData 构建产物启动成第二套知行；安装只替换 `/Applications/知行.app`，不触碰用户日历、任务、使命或偏好数据。

## 本地发行

- 提供 arm64 与 x86_64 的 Universal DMG。
- 产物为本机 ad-hoc 签名；不等同于 Developer ID 签名或 Apple 公证。
