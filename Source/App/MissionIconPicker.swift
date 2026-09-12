import CalendarCountdownCore
import SwiftUI

struct MissionIconPicker: View {
    @Binding var selection: String
    var tint: Color = .accentColor
    @State private var query = ""

    private var groups: [MissionSymbolGroup] {
        MissionSymbolCatalog.groups(matching: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                AppLocalization.text("mission.icon.search", defaultValue: "搜索图标"),
                text: $query
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("mission-icon-search")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 36), spacing: 6)],
                                spacing: 6
                            ) {
                                ForEach(group.symbols) { symbol in
                                    Button {
                                        selection = symbol.systemName
                                    } label: {
                                        Image(systemName: symbol.systemName)
                                            .frame(maxWidth: .infinity, minHeight: 28)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(
                                                        selection == symbol.systemName
                                                            ? tint.opacity(0.18)
                                                            : Color.secondary.opacity(0.08)
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(symbol.title)
                                    .accessibilityLabel(symbol.title)
                                    .accessibilityAddTraits(selection == symbol.systemName ? .isSelected : [])
                                    .appActionFocusEffectDisabled()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: MissionEditorLayout.iconPickerMaxHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.text("mission.icon.picker", defaultValue: "使命图标"))
    }
}

struct MissionColorPicker: View {
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.missionIdentity(selection))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.text("mission.color.current", defaultValue: "当前颜色"))
                    Text(MissionColor.resolve(selection).title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(MissionColor.allCases) { color in
                    Button {
                        selection = color.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    }
                                if MissionColor.resolve(selection) == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(checkmarkColor(for: color))
                                }
                            }
                            Text(color.title)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    MissionColor.resolve(selection) == color
                                        ? color.swiftUIColor.opacity(0.12)
                                        : Color.secondary.opacity(0.06)
                                )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    MissionColor.resolve(selection) == color
                                        ? color.swiftUIColor.opacity(0.55)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(MissionColor.resolve(selection) == color ? .isSelected : [])
                    .accessibilityIdentifier("mission-color-\(color.rawValue)")
                    .appActionFocusEffectDisabled()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.text("mission.color.picker", defaultValue: "使命颜色"))
        .accessibilityIdentifier("mission-color-picker")
    }

    private func checkmarkColor(for color: MissionColor) -> Color {
        switch color {
        case .yellow, .mint, .cyan:
            .black.opacity(0.78)
        default:
            .white
        }
    }
}
