import CalendarCountdownCore
import SwiftUI

enum ZhixingColor {
    static var contentBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var groupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    static var highlightStroke: Color {
        Color.white.opacity(0.34)
    }
}

/// An opaque-to-the-desktop canvas with enough internal color variation for
/// SwiftUI material surfaces to read as glass instead of flat white cards.
struct AppGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            ZhixingColor.contentBackground
            if !reduceTransparency, contrast != .increased {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10),
                        Color.cyan.opacity(colorScheme == .dark ? 0.07 : 0.045),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.07 : 0.46),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 16,
                    endRadius: 560
                )
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.055),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 8,
                    endRadius: 520
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum ZhixingMotion {
    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .snappy(duration: ZhixingMetrics.motionStandard)
    }

    static func fast(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: ZhixingMetrics.motionFast)
    }
}

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = ZhixingMetrics.cornerContainer
    var tint: Color = .clear
    var padded: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .padding(padded ? ZhixingMetrics.space16 : 0)
            .background { chrome }
    }

    private var usesSolidFill: Bool {
        reduceTransparency || contrast == .increased
    }

    private var chrome: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            if usesSolidFill {
                shape.fill(ZhixingColor.groupedBackground.opacity(colorScheme == .dark ? 0.92 : 0.96))
            } else {
                shape.fill(.thinMaterial)
                shape.fill(ZhixingColor.contentBackground.opacity(colorScheme == .dark ? 0.24 : 0.38))
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.42),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            if tint != .clear {
                shape.fill(tint.opacity(ZhixingMetrics.accentFillMaxOpacity))
            }
            shape.strokeBorder(strokeColor, lineWidth: strokeWidth)
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07),
            radius: 10,
            x: 0,
            y: 4
        )
    }

    private var strokeColor: Color {
        if contrast == .increased {
            return Color.primary.opacity(0.45)
        }
        let highlight = colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.42)
        if tint == .clear {
            return highlight
        }
        return tint.opacity(0.28)
    }

    private var strokeWidth: CGFloat {
        contrast == .increased ? 1 : ZhixingMetrics.glassStrokeWidth
    }
}

struct ContentSurface<Content: View>: View {
    var cornerRadius: CGFloat = ZhixingMetrics.cornerContainer
    var identity: Color? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .padding(ZhixingMetrics.space16)
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                Group {
                    if reduceTransparency || contrast == .increased {
                        shape.fill(ZhixingColor.groupedBackground.opacity(0.96))
                    } else {
                        shape.fill(.regularMaterial)
                        shape.fill(ZhixingColor.groupedBackground.opacity(colorScheme == .dark ? 0.34 : 0.48))
                    }
                }
                    .overlay {
                        shape.strokeBorder(
                            Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
                            lineWidth: contrast == .increased ? 1 : ZhixingMetrics.glassStrokeWidth
                        )
                    }
            }
            .overlay(alignment: .leading) {
                if let identity {
                    IdentityMark(color: identity, height: nil)
                        .padding(.vertical, ZhixingMetrics.space12)
                }
            }
    }
}

struct IdentityMark: View {
    var color: Color
    var height: CGFloat?

    var body: some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: ZhixingMetrics.identityMarkWidth, height: height)
            .accessibilityHidden(true)
    }
}

struct ModuleHeader: View {
    let title: String
    var subtitle: String
    var summary: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: ZhixingMetrics.space4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, ZhixingMetrics.space8)
        .accessibilityElement(children: .combine)
    }
}

struct MetaTag: View {
    var title: String
    var systemImage: String? = nil
    var tint: Color = .secondary
    var emphasized: Bool = false
    var identifier: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
        }
        .font(.caption2.weight(emphasized ? .semibold : .medium))
        .foregroundStyle(emphasized ? tint : Color.secondary)
        .padding(.horizontal, ZhixingMetrics.space8)
        .padding(.vertical, 3)
        .background(
            (emphasized ? tint.opacity(0.14) : Color.primary.opacity(0.06)),
            in: Capsule(style: .continuous)
        )
        .lineLimit(1)
        .accessibilityIdentifier(identifier ?? "meta-tag")
        .accessibilityLabel(title)
    }
}

/// A restrained mission identity label. Mission color belongs to the surface;
/// icon and text stay titanium gray so every task uses one visual grammar.
struct MissionTag: View {
    let title: String
    let systemImage: String
    let identity: Color
    var identifier: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(title)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.76 : 0.70))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(identity.opacity(colorScheme == .dark ? 0.30 : 0.22))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(identity.opacity(colorScheme == .dark ? 0.38 : 0.24), lineWidth: 0.6)
        }
        .lineLimit(1)
        .accessibilityIdentifier(identifier ?? "mission-tag")
        .accessibilityLabel(title)
    }
}

struct StatusCapsule: View {
    let title: String
    var systemImage: String
    var tint: Color
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(emphasized ? tint : Color.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(emphasized ? tint.opacity(0.14) : Color.primary.opacity(0.06))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(emphasized ? tint.opacity(0.42) : Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

struct PrimaryToolbarAction: View {
    let title: String
    let systemImage: String
    let help: String
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "mac-create-button")
        .appActionFocusEffectDisabled()
    }
}

struct CompletionRingButton: View {
    var isCompleted: Bool
    var tint: Color = .accentColor
    var accessibilityLabel: String
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isCompleted ? tint.opacity(0.35) : Color.secondary.opacity(0.45),
                        lineWidth: 1.6
                    )
                    .frame(
                        width: ZhixingMetrics.completionRingSize,
                        height: ZhixingMetrics.completionRingSize
                    )
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appActionFocusEffectDisabled()
        .accessibilityLabel(accessibilityLabel)
        .animation(ZhixingMotion.fast(reduceMotion: reduceMotion), value: isCompleted)
    }
}

struct ZhixingEmptyState: View {
    let systemImage: String
    let title: String
    let description: String
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(actionIdentifier ?? "empty-primary-action")
                    .appActionFocusEffectDisabled()
            }
        }
    }
}

struct FloatingStatusBanner: View {
    let message: String

    var body: some View {
        GlassSurface(cornerRadius: 20) {
            Text(message)
                .font(.callout)
                .padding(.horizontal, ZhixingMetrics.space16)
                .padding(.vertical, ZhixingMetrics.space8)
        }
        .clipShape(Capsule(style: .continuous))
        .padding(ZhixingMetrics.space16)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct SheetActionBar: View {
    var cancelTitle: String = "取消"
    var primaryTitle: String = "保存"
    var cancelIdentifier: String? = nil
    var primaryIdentifier: String? = nil
    var canSubmit: Bool
    var isBusy: Bool = false
    var showsPrimary: Bool = true
    var onCancel: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        HStack {
            Button(cancelTitle, role: .cancel, action: onCancel)
                .accessibilityIdentifier(cancelIdentifier ?? "sheet-cancel")
                .appActionFocusEffectDisabled()
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small)
            }
            if showsPrimary {
                Button(primaryTitle, action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier(primaryIdentifier ?? "sheet-save")
                    .appActionFocusEffectDisabled()
            }
        }
        .padding(.horizontal, ZhixingMetrics.space20)
        .padding(.vertical, ZhixingMetrics.space12)
        .frame(minHeight: 52)
        .background(.bar)
    }
}

struct ComposerSheetScaffold<Content: View>: View {
    let title: String
    var primaryTitle: String = "保存"
    var cancelIdentifier: String? = nil
    var primaryIdentifier: String? = nil
    var canSubmit: Bool
    var showsPrimary: Bool = true
    var width: CGFloat = 520
    var height: CGFloat = 560
    var onCancel: () -> Void
    var onSubmit: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, ZhixingMetrics.space20)
            .padding(.vertical, ZhixingMetrics.space12)
            Divider()
            content()
            Divider()
            SheetActionBar(
                primaryTitle: primaryTitle,
                cancelIdentifier: cancelIdentifier,
                primaryIdentifier: primaryIdentifier,
                canSubmit: canSubmit,
                showsPrimary: showsPrimary,
                onCancel: onCancel,
                onSubmit: onSubmit
            )
        }
        .frame(width: width, height: height)
        #else
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                            .accessibilityIdentifier(cancelIdentifier ?? "sheet-cancel")
                            .appActionFocusEffectDisabled()
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if showsPrimary {
                            Button(primaryTitle, action: onSubmit)
                                .disabled(!canSubmit)
                                .accessibilityIdentifier(primaryIdentifier ?? "sheet-save")
                                .appActionFocusEffectDisabled()
                        }
                    }
                }
        }
        #endif
    }
}

struct SidebarItemRow: View {
    let section: AppSection
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: ZhixingMetrics.space8) {
            Image(systemName: section.systemImage)
                .frame(width: 18)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.78))
            Text(section.title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.secondary : Color.secondary.opacity(0.62))
                    .fixedSize()
            }
        }
        .padding(.horizontal, ZhixingMetrics.space8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.title)
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(section.accessibilityIdentifier)
    }
}

struct SidebarUtilityRow: View {
    let title: String
    let systemImage: String
    var accessoryImage: String? = nil

    var body: some View {
        HStack(spacing: ZhixingMetrics.space8) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)
                .foregroundStyle(Color.secondary.opacity(0.86))
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: ZhixingMetrics.space8)
            if let accessoryImage {
                Image(systemName: accessoryImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, ZhixingMetrics.space8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SidebarListRowModifier<Background: View>: ViewModifier {
    let background: Background

    func body(content: Content) -> some View {
        content
            .listRowInsets(
                EdgeInsets(
                    top: ZhixingMetrics.space4,
                    leading: ZhixingMetrics.space8,
                    bottom: ZhixingMetrics.space4,
                    trailing: ZhixingMetrics.space8
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}

extension View {
    func sidebarListRow() -> some View {
        modifier(SidebarListRowModifier(background: Color.clear))
    }

    func sidebarListRow<Background: View>(background: Background) -> some View {
        modifier(SidebarListRowModifier(background: background))
    }
}

struct TaskBarCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .padding(.horizontal, ZhixingMetrics.space12)
            .padding(.vertical, ZhixingMetrics.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSheet, style: .continuous)
                if reduceTransparency || contrast == .increased {
                    shape.fill(ZhixingColor.groupedBackground.opacity(0.96))
                } else {
                    shape.fill(.regularMaterial)
                    shape.fill(ZhixingColor.groupedBackground.opacity(colorScheme == .dark ? 0.28 : 0.42))
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSheet, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.14)
                            : Color.white.opacity(0.72),
                        lineWidth: ZhixingMetrics.glassStrokeWidth
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.055),
                radius: 7,
                x: 0,
                y: 3
            )
            .contentShape(
                RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSheet, style: .continuous)
            )
    }
}

struct TaskListViewportSnapshot: Equatable {
    var globalFrame: CGRect = .zero
    var visibleRect: CGRect = .zero
}

private struct TaskListViewportKey: EnvironmentKey {
    static let defaultValue = TaskListViewportSnapshot()
}

extension EnvironmentValues {
    var taskListViewport: TaskListViewportSnapshot {
        get { self[TaskListViewportKey.self] }
        set { self[TaskListViewportKey.self] = newValue }
    }
}

struct TaskCompletedTrailChrome: ViewModifier {
    var index: Int

    @Environment(\.taskListViewport) private var viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isKeyboardFocused: Bool
    @AccessibilityFocusState private var isA11yFocused: Bool
    @State private var isHovering = false
    @State private var normalizedY: Double?

    private var highContrast: Bool {
        reduceTransparency || contrast == .increased
    }

    private var appearance: CompletedTrailAppearance {
        CompletedTrailPresentation.resolve(
            index: index,
            normalizedY: normalizedY,
            isHighlighted: isHovering || isKeyboardFocused || isA11yFocused,
            highContrast: highContrast
        )
    }

    func body(content: Content) -> some View {
        content
            .saturation(appearance.saturation)
            .opacity(appearance.opacity)
            .overlay {
                RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSheet, style: .continuous)
                    .fill(ZhixingColor.contentBackground.opacity(appearance.veil))
                    .allowsHitTesting(false)
            }
            .focusable()
            .focused($isKeyboardFocused)
            .focusEffectDisabled()
            .accessibilityFocused($isA11yFocused)
            .onHover { isHovering = $0 }
            .background {
                GeometryReader { proxy in
                    let named = proxy.frame(in: .named("zhixing.tasks"))
                    let global = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { updateNormalizedY(named: named, global: global) }
                        .onChange(of: named) { _, value in
                            updateNormalizedY(named: value, global: global)
                        }
                        .onChange(of: global) { _, value in
                            updateNormalizedY(named: named, global: value)
                        }
                        .onChange(of: viewport) { _, _ in
                            updateNormalizedY(named: named, global: global)
                        }
                }
            }
            .animation(ZhixingMotion.standard(reduceMotion: reduceMotion), value: appearance.opacity)
            .animation(ZhixingMotion.standard(reduceMotion: reduceMotion), value: appearance.veil)
    }

    private func updateNormalizedY(named: CGRect, global: CGRect) {
        if viewport.visibleRect.height > 1 {
            normalizedY = (named.midY - viewport.visibleRect.minY) / viewport.visibleRect.height
            return
        }
        if viewport.globalFrame.height > 1 {
            normalizedY = (global.midY - viewport.globalFrame.minY) / viewport.globalFrame.height
            return
        }
        normalizedY = nil
    }
}

struct SidebarSelectionBackground: View {
    var isSelected: Bool

    var body: some View {
        if isSelected {
            GlassSurface(cornerRadius: 12, tint: .accentColor) {
                Color.clear
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}

extension View {
    func zhixingListRow(featured: Bool = false) -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: featured ? ZhixingMetrics.space12 : ZhixingMetrics.space8,
                    leading: ZhixingMetrics.pageInset,
                    bottom: featured ? ZhixingMetrics.space12 : ZhixingMetrics.space8,
                    trailing: ZhixingMetrics.pageInset
                )
            )
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    func zhixingHoverOpacity(isPersistent: Bool, idleOpacity: Double = 0.28) -> some View {
        modifier(HoverOpacityModifier(isPersistent: isPersistent, idleOpacity: idleOpacity))
    }
}

private struct HoverOpacityModifier: ViewModifier {
    var isPersistent: Bool
    var idleOpacity: Double
    @State private var hovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .opacity(isPersistent || hovering ? 1 : idleOpacity)
            .onHover { hovering = $0 }
        #else
        content
        #endif
    }
}

extension View {
    @ViewBuilder
    func composerSheetFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        self
        #endif
    }
}
