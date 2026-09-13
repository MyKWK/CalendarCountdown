import CalendarCountdownCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AddMissionSheet: View {
    let initialColor: String
    let onSave: (CreateMissionCommand) -> Void

    init(
        initialColor: String = MissionColor.defaultValue.rawValue,
        onSave: @escaping (CreateMissionCommand) -> Void
    ) {
        self.initialColor = MissionColor.canonicalStorageValue(initialColor)
        self.onSave = onSave
    }

    var body: some View {
        MissionEditorSheet(initialColor: initialColor, onCreate: onSave)
    }
}

struct MissionEditorSheet: View {
    private let existing: MissionDefinition?
    private let onCreate: ((CreateMissionCommand) -> Void)?
    private let onUpdate: ((PatchMissionCommand) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var icon: String
    @State private var color: String
    @State private var targetDateEnabled: Bool
    @State private var targetDate: Date
    @State private var showingIconPicker = false

    init(
        initialColor: String = MissionColor.defaultValue.rawValue,
        onCreate: @escaping (CreateMissionCommand) -> Void
    ) {
        existing = nil
        self.onCreate = onCreate
        onUpdate = nil
        _title = State(initialValue: "")
        _description = State(initialValue: "")
        _icon = State(initialValue: MissionSymbolCatalog.defaultSystemName)
        _color = State(initialValue: MissionColor.canonicalStorageValue(initialColor))
        _targetDateEnabled = State(initialValue: false)
        _targetDate = State(initialValue: Date())
    }

    init(mission: MissionDefinition, onUpdate: @escaping (PatchMissionCommand) -> Void) {
        existing = mission
        onCreate = nil
        self.onUpdate = onUpdate
        _title = State(initialValue: mission.title)
        _description = State(initialValue: mission.markdownDescription ?? "")
        _icon = State(initialValue: MissionSymbolCatalog.resolved(mission.icon))
        _color = State(initialValue: MissionColor.canonicalStorageValue(mission.color))
        _targetDateEnabled = State(initialValue: mission.targetDate != nil)
        _targetDate = State(initialValue: mission.targetDate?.startOfDay(in: .current) ?? Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                nameChrome
                    .padding(.horizontal, MissionEditorLayout.horizontalInset)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: MissionEditorLayout.sectionSpacing) {
                        editorCard(
                            title: AppLocalization.text("mission.color.field", defaultValue: "颜色"),
                            identifier: "mission-color-field"
                        ) {
                            MissionColorPicker(selection: $color)
                        }
                        editorCard(title: "说明（支持 Markdown）") {
                            ComposerMultilineField(
                                title: AppLocalization.text(
                                    "mission.description.placeholder",
                                    defaultValue: "说明"
                                ),
                                text: $description,
                                lineLimit: 8...16,
                                onSubmit: submit
                            )
                            Text("回车换行；⌘↩ 保存。")
                                .font(.caption)
                                .zhixingForeground(.supporting)
                        }
                        editorCard(
                            title: AppLocalization.text("mission.goal.field", defaultValue: "目标")
                        ) {
                            Toggle(
                                AppLocalization.text("mission.target_date", defaultValue: "目标日期"),
                                isOn: $targetDateEnabled
                            )
                            if targetDateEnabled {
                                DatePicker(
                                    AppLocalization.text("mission.due", defaultValue: "截止"),
                                    selection: $targetDate,
                                    displayedComponents: .date
                                )
                            }
                        }
                    }
                    .padding(.horizontal, MissionEditorLayout.horizontalInset)
                    .padding(.vertical, MissionEditorLayout.verticalInset)
                }
                .scrollBounceBehavior(.basedOnSize)
                Divider()
                footerBar
            }
            .navigationTitle(
                existing == nil
                    ? AppLocalization.text("mission.create.title", defaultValue: "新建使命")
                    : AppLocalization.text("mission.edit.title", defaultValue: "编辑使命")
            )
        }
        .accessibilityIdentifier("mission-editor")
        .modifier(MissionEditorChrome())
    }

    private var nameChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            iconChooser
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.text("mission.name.field", defaultValue: "名称"))
                    .font(.caption.weight(.medium))
                    .zhixingForeground(.supporting)
                TextField(
                    AppLocalization.text("mission.title.placeholder", defaultValue: "标题"),
                    text: $title
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("mission-title-field")
                .onSubmit(submit)
            }
        }
    }

    private var iconChooser: some View {
        Button {
            showingIconPicker.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.missionIdentity(color))
                    .frame(
                        width: MissionEditorLayout.identityIconSize,
                        height: MissionEditorLayout.identityIconSize
                    )
                Image(systemName: MissionSymbolCatalog.resolved(icon))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(showingIconPicker ? 0.28 : 0.10),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .frame(
            width: MissionEditorLayout.identityIconHitSize,
            height: MissionEditorLayout.identityIconHitSize
        )
        .contentShape(Circle())
        .appActionFocusEffectDisabled()
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        .help(MissionSymbolCatalog.title(for: icon))
        .accessibilityLabel(AppLocalization.text("mission.icon.field", defaultValue: "图标"))
        .accessibilityValue(MissionSymbolCatalog.title(for: icon))
        .accessibilityHint(AppLocalization.text("mission.icon.hint", defaultValue: "点按以选择图标"))
        .accessibilityIdentifier("mission-icon-button")
        .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
            iconPickerPopover
        }
    }

    @ViewBuilder
    private var iconPickerPopover: some View {
        MissionIconPicker(
            selection: iconSelection,
            tint: Color.missionIdentity(color)
        )
        .padding(12)
        #if os(macOS)
        .frame(width: MissionEditorLayout.iconPopoverWidth)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private var iconSelection: Binding<String> {
        Binding(
            get: { icon },
            set: { newValue in
                icon = newValue
                showingIconPicker = false
            }
        )
    }

    private var footerBar: some View {
        SheetActionBar(
            cancelIdentifier: "mission-editor-cancel",
            primaryIdentifier: "mission-editor-save",
            canSubmit: canSubmit,
            onCancel: { dismiss() },
            onSubmit: submit
        )
    }

    private func editorCard<Content: View>(
        title: String,
        identifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ZhixingTypography.rowTitle)
                .zhixingForeground(.supporting)
            content()
        }
        .padding(MissionEditorLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: MissionEditorLayout.cardCornerRadius)
                .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: MissionEditorLayout.cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "mission-card-\(title)")
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        save()
        dismiss()
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = targetDateEnabled ? LocalDate.from(targetDate, timeZone: .current) : nil
        if let onCreate {
            onCreate(
                CreateMissionCommand(
                    title: trimmedTitle,
                    markdownDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    color: color,
                    icon: icon,
                    targetDate: date
                )
            )
            return
        }
        onUpdate?(
            PatchMissionCommand(
                title: trimmedTitle,
                markdownDescription: trimmedDescription,
                color: color,
                icon: icon,
                targetDate: date,
                clearTargetDate: date == nil && existing?.targetDate != nil
            )
        )
    }
}

private struct MissionEditorChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        let size = MissionEditorLayout.fittingSize(available: Self.availableWorkArea)
        content
            .frame(
                minWidth: min(MissionEditorLayout.minWidth, size.width),
                idealWidth: size.width,
                maxWidth: size.width,
                minHeight: min(MissionEditorLayout.minHeight, size.height),
                idealHeight: size.height,
                maxHeight: size.height
            )
            .padding(0)
        #else
        content
        #endif
    }

    #if os(macOS)
    private static var availableWorkArea: CGSize {
        NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
    }
    #endif
}
