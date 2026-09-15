import Carbon
import CalendarCountdownCore
import Combine
import Foundation
import SwiftUI

enum AppShortcutAction: Equatable {
    case addInCurrentModule
    case addCountdown
    case addTask
    case addMission
    case addHabit
    case selectSection(AppSection)
}

struct ShortcutCommandMenu: Commands {
    @ObservedObject var shortcuts: AppShortcutCoordinator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(shortcuts.currentSection.createActionTitle) {
                shortcuts.request(.addInCurrentModule)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("快捷操作") {
            Button("新建倒数日") {
                shortcuts.request(.addCountdown)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("新建任务") {
                shortcuts.request(.addTask)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("新建使命") {
                shortcuts.request(.addMission)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("新建打卡") {
                shortcuts.request(.addHabit)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Button("打开倒数日") {
                shortcuts.request(.selectSection(.countdown))
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("打开任务清单") {
                shortcuts.request(.selectSection(.tasks))
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("打开使命清单") {
                shortcuts.request(.selectSection(.missions))
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("打开打卡") {
                shortcuts.request(.selectSection(.habits))
            }
            .keyboardShortcut("4", modifiers: .command)
        }
    }
}

struct AppShortcutRequest: Identifiable, Equatable {
    let id = UUID()
    let action: AppShortcutAction
}

enum GlobalShortcutStatus: Equatable {
    case active
    case disabled
    case unavailable(OSStatus)

    var title: String {
        switch self {
        case .active:
            "已启用"
        case .disabled:
            "已关闭"
        case .unavailable:
            "未能注册"
        }
    }

    var detail: String {
        switch self {
        case .active:
            "按下后会将知行带到前台并打开主界面。"
        case .disabled:
            "全局唤起已关闭。"
        case let .unavailable(status):
            "此组合键可能已被其它应用或系统占用（错误码 \(status)）。请关闭冲突应用后重新启用。"
        }
    }
}

@MainActor
final class AppShortcutCoordinator: ObservableObject {
    private enum Keys {
        static let globalWakeEnabled = "shortcuts.globalWakeEnabled"
    }

    static let globalWakeDisplay = "⇧⌘E"

    @Published var currentSection: AppSection = .countdown
    @Published var globalWakeEnabled: Bool {
        didSet {
            defaults.set(globalWakeEnabled, forKey: Keys.globalWakeEnabled)
            updateGlobalWakeRegistration()
        }
    }
    @Published private(set) var globalWakeStatus: GlobalShortcutStatus = .disabled
    @Published private(set) var request: AppShortcutRequest?

    private let defaults: UserDefaults
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var onGlobalWake: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.globalWakeEnabled) == nil {
            globalWakeEnabled = true
        } else {
            globalWakeEnabled = defaults.bool(forKey: Keys.globalWakeEnabled)
        }
    }

    func startGlobalWake(onTriggered: @escaping () -> Void) {
        onGlobalWake = onTriggered
        updateGlobalWakeRegistration()
    }

    func request(_ action: AppShortcutAction) {
        request = AppShortcutRequest(action: action)
    }

    private func updateGlobalWakeRegistration() {
        unregisterGlobalWake()
        guard globalWakeEnabled else {
            globalWakeStatus = .disabled
            return
        }

        installEventHandlerIfNeeded()
        guard eventHandler != nil else { return }
        var hotKeyReference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5A484B59), id: 1) // "ZHKY"
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        if status == noErr {
            hotKey = hotKeyReference
            globalWakeStatus = .active
        } else {
            globalWakeStatus = .unavailable(status)
        }
    }

    private func unregisterGlobalWake() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleGlobalHotKey,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            globalWakeStatus = .unavailable(status)
        }
    }

    private static let handleGlobalHotKey: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let userDataAddress = UInt(bitPattern: userData)
        // Carbon dispatches application event handlers on the main event loop.
        // Keep the callback synchronous so its actor boundary reflects that API.
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: userDataAddress) else { return }
            let coordinator = Unmanaged<AppShortcutCoordinator>.fromOpaque(pointer).takeUnretainedValue()
            coordinator.onGlobalWake?()
        }
        return noErr
    }
}
