import CalendarCountdownCore
import SwiftUI

struct MobileSettingsView: View {
    @ObservedObject var session: MobileAppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("日历与提醒") {
                LabeledContent("日历权限", value: session.model.accessState.rawValue)
                Button("请求日历访问") {
                    Task { await session.model.requestAccess() }
                }
                .accessibilityIdentifier("mobile-request-calendar")
                Text("提醒事项权限会在你开启任务或习惯投影时再请求，启动时不会同时弹出两个系统框。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("同步") {
                LabeledContent("iCloud 模式", value: session.workspace.cloudMode.rawValue)
                Toggle(
                    "iCloud 同步",
                    isOn: Binding(
                        get: { session.workspace.cloudMode == .iCloud },
                        set: { session.workspace.setCloudMode($0) }
                    )
                )
                .accessibilityIdentifier("mobile-icloud-toggle")
            }
            Section("容器") {
                LabeledContent("App Group") {
                    Text(ProductConstants.appGroupIdentifier)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
                if let root = try? MobileContainerLocator.appGroupRoot() {
                    LabeledContent("共享目录") {
                        Text(root.path)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("无法访问正式 App Group 容器。Widget 不会读到本机快照。")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("设置")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}

struct MobileSyncStatusView: View {
    @ObservedObject var session: MobileAppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let status = try? session.workspace.workspace?.cloud.status()
        Form {
            Section("CloudKit") {
                LabeledContent("模式", value: status?.mode.rawValue ?? session.workspace.cloudMode.rawValue)
                LabeledContent("账号", value: status?.account.rawValue ?? "unknown")
                LabeledContent("待上传", value: String(status?.pendingOutbox ?? 0))
                LabeledContent("待回放", value: String(status?.pendingInbox ?? 0))
                LabeledContent("冲突", value: String(status?.openConflicts ?? 0))
                LabeledContent(
                    "上次拉取",
                    value: status?.lastFetchAt.map(RFC3339.utcString(from:)) ?? "尚未成功"
                )
                LabeledContent(
                    "上次推送",
                    value: status?.lastSendAt.map(RFC3339.utcString(from:)) ?? "尚未成功"
                )
            }
            Section {
                Button("立即同步") {
                    session.refresh()
                }
            }
        }
        .navigationTitle("同步状态")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}
