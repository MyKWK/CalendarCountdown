import CalendarCountdownCore
import Foundation

public enum CloudKitEngineFactory {
    public static func make(
        workspace: Workspace,
        profileSession: CloudProfileSession,
        automaticallySync: Bool = true,
        transport: (any CloudSyncTransporting)? = nil
    ) -> CloudKitSyncEngine {
        CloudKitSyncEngine(
            workspace: workspace,
            automaticallySync: automaticallySync,
            profileSession: profileSession,
            transport: transport
        )
    }

    public static func make(
        workspace: Workspace,
        profileSession: CloudProfileSession?,
        automaticallySync: Bool = true,
        transport: (any CloudSyncTransporting)? = nil
    ) throws -> CloudKitSyncEngine {
        guard let profileSession else {
            throw DomainError(
                code: .icloudUnavailable,
                message: "开启 iCloud 同步前必须绑定当前 CloudProfileSession，不能绕过账号隔离。"
            )
        }
        return make(
            workspace: workspace,
            profileSession: profileSession,
            automaticallySync: automaticallySync,
            transport: transport
        )
    }
}
