# 日历倒数 1.0.2（macOS Universal）

## 安装 App

1. 打开 `CalendarCountdown-1.0.2-macos-universal.dmg`。
2. 将“日历倒数.app”拖到“Applications”快捷方式。
3. 此 GitHub 构建为 ad-hoc 签名、尚未经过 Apple 公证。首次打开若被 macOS 阻止，请在 Finder 中按住 Control 点击 App，选择“打开”，或前往“系统设置 → 隐私与安全性”确认打开。
4. 在 App 中点击“授权日历访问”。只有在你明确新建或导入时，App 才会写入选定的 Apple 日历。

## JSON 导入与导出

DMG 只附带匿名格式示例，不包含开发者或用户的私人纪念日：

- `导入格式示例.json`：批量写入 Apple 日历的格式。
- `追踪清单格式示例.json`：当前追踪纪念日的导出格式。

在 App 工具栏点击“导出追踪清单”，即可导出当前可见、正在追踪的重要日。Apple 日历仍是事件事实源，追踪 JSON 只是便携索引。

## CLI（可选）

DMG 根目录中的 `calcount` 是同时支持 Apple Silicon 与 Intel Mac 的 Universal 命令行工具。示例：

```bash
/Volumes/日历倒数\ 1.0.2/calcount version
/Volumes/日历倒数\ 1.0.2/calcount auth
/Volumes/日历倒数\ 1.0.2/calcount import "/Volumes/日历倒数 1.0.2/导入格式示例.json" --dry-run
/Volumes/日历倒数\ 1.0.2/calcount tracking export --output ~/Desktop/important-days.json
```

## 签名状态

本构建使用 ad-hoc 签名，没有 Developer ID Application 证书，也没有 Apple notarization ticket。代码签名完整性已校验，但它不等同于可无提示安装的 Apple 公证发行版。
