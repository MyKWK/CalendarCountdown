# 知行 1.0.10

## 主线整合

- 固定科技风主题，使命可独立选择颜色；完善使命编辑器布局与状态栏展示。
- 汇入 iPhone、iPad、跨平台 Swift Core 和 HarmonyOS 的当前实现，并以 `Platforms/iOS` 保持唯一移动端架构。
- 使用进程级单实例锁与安全安装流程，避免 DerivedData 构建副本变成第二套知行。

## 本地交付

- 产物：`CalendarCountdown-1.0.10-macos-universal.dmg`。
- 验证：Universal（arm64、x86_64）、DMG 完整性、应用签名和安装版本均已在本机验证。
- 签名：本机 ad-hoc 签名，不代表 Developer ID 签名或 Apple 公证。
