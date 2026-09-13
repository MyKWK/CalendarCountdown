import CalendarCountdownCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ZhixingColor {
    static var contentBackground: Color {
        Color(light: (0.976, 0.973, 0.965), dark: (0.075, 0.075, 0.073))
    }

    static var groupedBackground: Color {
        Color(light: (0.945, 0.941, 0.932), dark: (0.112, 0.112, 0.108))
    }

    static var sidebarBackground: Color {
        Color(light: (0.938, 0.934, 0.925), dark: (0.092, 0.092, 0.089))
    }

    static var elevatedBackground: Color {
        Color(light: (1, 1, 0.996), dark: (0.142, 0.142, 0.137))
    }

    static var hairline: Color {
        Color.primary.opacity(0.085)
    }

    static var highlightStroke: Color {
        Color.white.opacity(0.34)
    }

    /// Cool titanium-gray text scale. Regular content deliberately avoids literal
    /// black/white so long sidebar and list surfaces read calmer, closer to the
    /// reference Codex sidebar than the system's near-black label color. Increase
    /// Contrast steps back toward full-strength system labels for legibility.
    static func text(
        _ tone: ZhixingTextTone,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Color {
        if contrast == .increased {
            switch tone {
            case .heading, .body: return .primary
            case .supporting, .faint: return .secondary
            }
        }
        switch tone {
        case .heading:
            return colorScheme == .dark
                ? Color(red: 0.88, green: 0.90, blue: 0.94)
                : Color(red: 0.24, green: 0.27, blue: 0.34)
        case .body:
            return colorScheme == .dark
                ? Color(red: 0.78, green: 0.81, blue: 0.87)
                : Color(red: 0.32, green: 0.36, blue: 0.44)
        case .supporting:
            return colorScheme == .dark
                ? Color(red: 0.64, green: 0.68, blue: 0.75)
                : Color(red: 0.41, green: 0.45, blue: 0.53)
        case .faint:
            return colorScheme == .dark
                ? Color(red: 0.50, green: 0.54, blue: 0.61)
                : Color(red: 0.53, green: 0.56, blue: 0.62)
        }
    }
}

/// Roles in the shared titanium-gray text scale. Use with `.zhixingForeground(_:)`
/// instead of ad hoc `.foregroundStyle(.primary)` / opacity numbers so every
/// Zhixing-styled surface stays on one centralized, accessibility-aware ramp.
enum ZhixingTextTone {
    /// Titles: sidebar brand title, page/module titles, row and card titles, empty-state titles.
    case heading
    /// Regular sidebar and list body text.
    case body
    /// Secondary descriptive text (subtitles, captions).
    case supporting
    /// Faint meta text (counts, timestamps, disabled-feeling labels).
    case faint
}

private struct ZhixingTextToneModifier: ViewModifier {
    let tone: ZhixingTextTone
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.foregroundStyle(ZhixingColor.text(tone, colorScheme: colorScheme, contrast: contrast))
    }
}

extension View {
    /// Applies the shared titanium-gray text tone. Prefer this over
    /// `.foregroundStyle(.primary/.secondary)` on Zhixing-styled surfaces (sidebar,
    /// headers, list rows) to keep color centralized and Increase-Contrast aware.
    func zhixingForeground(_ tone: ZhixingTextTone) -> some View {
        modifier(ZhixingTextToneModifier(tone: tone))
    }
}

/// Shared type scale. Every case is a system Dynamic Type style (no custom fonts);
/// weight is capped at `.medium` so titles read closer to Codex's light sidebar
/// instead of stacking `.semibold` across every hierarchy level.
enum ZhixingTypography {
    static let sidebarBrandTitle: Font = .headline.weight(.medium)
    static let sidebarSectionTitle: Font = .caption.weight(.medium)
    static let sidebarItem: Font = .callout
    static let sidebarItemSelected: Font = .callout.weight(.medium)

    /// Page/module big titles (Countdown, Tasks, Missions, Habits headers).
    static let pageTitle: Font = .title3.weight(.medium)
    /// Card-level titles (mission cards, featured countdown row).
    static let cardTitle: Font = .headline.weight(.medium)
    /// List row titles (task rows, habit rows, countdown rows).
    static let rowTitle: Font = .subheadline.weight(.medium)
    /// Empty-state titles.
    static let emptyStateTitle: Font = .title3.weight(.medium)
    static let featuredCountdownValue: Font = .system(.title2, design: .rounded, weight: .medium).monospacedDigit()
    static let countdownValue: Font = .headline.weight(.medium).monospacedDigit()
}

/// An opaque-to-the-desktop canvas with enough internal color variation for
/// SwiftUI material surfaces to read as glass instead of flat white cards.
struct AppGlassBackdrop: View {
    var body: some View {
        ZhixingColor.contentBackground
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
            shape.fill(
                usesSolidFill
                    ? ZhixingColor.elevatedBackground
                    : ZhixingColor.elevatedBackground.opacity(colorScheme == .dark ? 0.82 : 0.92)
            )
            if tint != .clear {
                shape.fill(tint.opacity(colorScheme == .dark ? 0.07 : 0.055))
            }
            shape.strokeBorder(strokeColor, lineWidth: strokeWidth)
        }
    }

    private var strokeColor: Color {
        if contrast == .increased {
            return Color.primary.opacity(0.45)
        }
        let highlight = colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.07)
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
                    shape.fill(
                        reduceTransparency || contrast == .increased
                            ? ZhixingColor.elevatedBackground
                            : ZhixingColor.elevatedBackground.opacity(colorScheme == .dark ? 0.78 : 0.90)
                    )
                }
                    .overlay {
                        shape.strokeBorder(
                            Color.primary.opacity(contrast == .increased ? 0.35 : 0.075),
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
                .font(ZhixingTypography.pageTitle)
                .zhixingForeground(.heading)
            Text(subtitle)
                .font(.callout)
                .zhixingForeground(.supporting)
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .zhixingForeground(.faint)
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
        }
        .font(.caption2.weight(emphasized ? .semibold : .medium))
        .foregroundStyle(
            emphasized
                ? tint
                : ZhixingColor.text(.supporting, colorScheme: colorScheme, contrast: contrast)
        )
        .padding(.horizontal, emphasized ? ZhixingMetrics.space8 : 0)
        .padding(.vertical, emphasized ? 3 : 0)
        .background(emphasized ? tint.opacity(0.12) : Color.clear, in: Capsule(style: .continuous))
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(title)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(
            ZhixingColor.text(.supporting, colorScheme: colorScheme, contrast: contrast)
        )
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(identity.opacity(colorScheme == .dark ? 0.13 : 0.10))
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(
            emphasized
                ? tint
                : ZhixingColor.text(.body, colorScheme: colorScheme, contrast: contrast)
        )
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
        .buttonStyle(CodexPrimaryButtonStyle())
        .help(help)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "mac-create-button")
        .appActionFocusEffectDisabled()
    }
}

struct CodexPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.primary.opacity(configuration.isPressed ? 0.78 : 0.94), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct CodexIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        VStack(spacing: ZhixingMetrics.space12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .zhixingForeground(.faint)
            Text(title)
                .font(.headline.weight(.medium))
                .zhixingForeground(.heading)
            Text(description)
                .font(.callout)
                .zhixingForeground(.supporting)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(CodexPrimaryButtonStyle())
                    .accessibilityIdentifier(actionIdentifier ?? "empty-primary-action")
                    .appActionFocusEffectDisabled()
            }
        }
        .padding(ZhixingMetrics.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FloatingStatusBanner: View {
    let message: String

    var body: some View {
        GlassSurface(cornerRadius: 20) {
            Text(message)
                .font(.callout)
                .zhixingForeground(.body)
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
                    .font(ZhixingTypography.cardTitle)
                    .zhixingForeground(.heading)
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: ZhixingMetrics.space8) {
            Image(systemName: section.systemImage)
                .frame(width: 18)
                .foregroundStyle(ZhixingColor.text(
                    isSelected ? .heading : .supporting,
                    colorScheme: colorScheme,
                    contrast: contrast
                ))
            Text(section.title)
                .font(isSelected ? ZhixingTypography.sidebarItemSelected : ZhixingTypography.sidebarItem)
                .zhixingForeground(isSelected ? .heading : .body)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .zhixingForeground(isSelected ? .supporting : .faint)
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
                .zhixingForeground(.supporting)
            Text(title)
                .font(ZhixingTypography.sidebarItem)
                .zhixingForeground(.body)
                .lineLimit(1)
            Spacer(minLength: ZhixingMetrics.space8)
            if let accessoryImage {
                Image(systemName: accessoryImage)
                    .font(.caption2.weight(.semibold))
                    .zhixingForeground(.faint)
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
    @State private var isHovering = false

    var body: some View {
        content()
            .padding(.horizontal, ZhixingMetrics.space12)
            .padding(.vertical, ZhixingMetrics.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSheet, style: .continuous)
                shape.fill(
                    reduceTransparency || contrast == .increased
                        ? ZhixingColor.elevatedBackground
                        : Color.primary.opacity(isHovering ? 0.055 : 0.025)
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSheet, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isHovering ? 0.11 : 0.055),
                        lineWidth: ZhixingMetrics.glassStrokeWidth
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSheet, style: .continuous)
            )
            .onHover { isHovering = $0 }
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.075))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.055), lineWidth: ZhixingMetrics.glassStrokeWidth)
                }
        } else {
            Color.clear
        }
    }
}

private extension Color {
    init(light: (Double, Double, Double), dark: (Double, Double, Double)) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let values = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let values = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
        })
        #endif
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
