import CalendarCountdownCore
import CoreImage
import SwiftUI

private struct AppWindowGlassActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appWindowGlassActive: Bool {
        get { self[AppWindowGlassActiveKey.self] }
        set { self[AppWindowGlassActiveKey.self] = newValue }
    }
}

extension View {
    func appGlassScrollBackground() -> some View {
        modifier(AppGlassScrollBackgroundModifier())
    }

    @ViewBuilder
    func appMainWindowGlass(
        enabled: Bool,
        transparency: Double,
        blurStrength: WindowGlassAppearance.BlurStrength
    ) -> some View {
        #if os(macOS)
        background {
            WindowGlassProbeRepresentable(
                enabled: enabled,
                transparency: transparency,
                blurStrength: blurStrength
            )
                .allowsHitTesting(false)
        }
        #else
        self
        #endif
    }
}

private struct AppGlassScrollBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color.clear)
    }
}

#if os(macOS)
import AppKit

private struct WindowGlassProbeRepresentable: NSViewRepresentable {
    var enabled: Bool
    var transparency: Double
    var blurStrength: WindowGlassAppearance.BlurStrength

    func makeNSView(context: Context) -> WindowGlassProbeView {
        WindowGlassProbeView()
    }

    func updateNSView(_ view: WindowGlassProbeView, context: Context) {
        view.apply(
            enabled: enabled,
            transparency: transparency,
            blurStrength: blurStrength
        )
    }
}

private final class WindowGlassProbeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        WindowGlassBackdropController.shared.attach(to: window)
        WindowGlassBackdropController.shared.refresh()
    }

    func apply(
        enabled: Bool,
        transparency: Double,
        blurStrength: WindowGlassAppearance.BlurStrength
    ) {
        WindowGlassBackdropController.shared.update(
            enabled: enabled,
            transparency: transparency,
            blurStrength: blurStrength
        )
        WindowGlassBackdropController.shared.attach(to: window)
        WindowGlassBackdropController.shared.refresh()
    }
}

@MainActor
private final class WindowGlassBackdropController {
    static let shared = WindowGlassBackdropController()

    private let identifier = NSUserInterfaceItemIdentifier("app.window.glass.backdrop")
    private weak var window: NSWindow?
    private var enabled = false
    private var transparency = WindowGlassAppearance.defaultTransparency
    private var blurStrength = WindowGlassAppearance.defaultBlurStrength
    private var refreshScheduled = false
    private weak var configuredWindow: NSWindow?
    private var configuredForGlass: Bool?

    func update(
        enabled: Bool,
        transparency: Double,
        blurStrength: WindowGlassAppearance.BlurStrength
    ) {
        self.enabled = enabled
        self.transparency = WindowGlassAppearance.clamped(transparency)
        self.blurStrength = blurStrength
    }

    func attach(to window: NSWindow?) {
        self.window = window
    }

    func refresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.applyNow()
        }
    }

    private var glassAllowed: Bool {
        WindowGlassAppearance.isUserFacingGlassActive(
            enabledFlag: enabled,
            reduceTransparency: false
        )
    }

    private func applyNow() {
        guard let window, let contentView = window.contentView else { return }
        if glassAllowed {
            configureWindowIfNeeded(window, glass: true)
            let backdrop = existingBackdrop(in: contentView) ?? makeBackdrop()
            if backdrop.superview !== contentView {
                contentView.addSubview(backdrop, positioned: .below, relativeTo: nil)
            }
            backdrop.frame = contentView.bounds
            backdrop.autoresizingMask = [.width, .height]
            backdrop.apply(transparency: transparency, blurStrength: blurStrength)
            makeAncestorsClear(from: contentView)
            applyTranslucency(to: contentView, skipping: backdrop)
        } else {
            // The normal full-size title-bar configuration is installed while
            // AppDelegate creates the window. Do not rewrite NSWindow chrome on
            // every SwiftUI update: doing so during AppKit's constraint pass can
            // recursively invalidate the hosting view and terminate the app.
            if configuredWindow === window, configuredForGlass == true {
                configureWindowIfNeeded(window, glass: false)
            }
            if let backdrop = existingBackdrop(in: contentView) {
                backdrop.removeFromSuperview()
            }
        }
    }

    private func configureWindowIfNeeded(_ window: NSWindow, glass: Bool) {
        guard configuredWindow !== window || configuredForGlass != glass else { return }
        configuredWindow = window
        configuredForGlass = glass

        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.hasShadow = true
        window.titlebarSeparatorStyle = .none
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.isMovableByWindowBackground = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = glass ? NSColor.clear.cgColor : NSColor.windowBackgroundColor.cgColor
    }

    private func existingBackdrop(in contentView: NSView) -> WindowGlassBackdropView? {
        contentView.subviews.first { $0.identifier == identifier } as? WindowGlassBackdropView
    }

    private func makeBackdrop() -> WindowGlassBackdropView {
        let backdrop = WindowGlassBackdropView()
        backdrop.identifier = identifier
        return backdrop
    }

    private func makeAncestorsClear(from view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func applyTranslucency(to view: NSView, skipping backdrop: NSView) {
        if view === backdrop { return }

        if let visual = view as? NSVisualEffectView {
            visual.blendingMode = .withinWindow
            visual.state = .active
        }
        if let scroll = view as? NSScrollView {
            scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
        }
        if let table = view as? NSTableView {
            table.backgroundColor = .clear
        }
        if let split = view as? NSSplitView {
            split.wantsLayer = true
            split.layer?.backgroundColor = NSColor.clear.cgColor
        }

        for subview in view.subviews where subview !== backdrop {
            applyTranslucency(to: subview, skipping: backdrop)
        }
    }

    private func restoreOpaqueChrome(in view: NSView) {
        if let scroll = view as? NSScrollView {
            scroll.drawsBackground = true
            scroll.contentView.drawsBackground = true
        }
        if let table = view as? NSTableView {
            table.backgroundColor = .windowBackgroundColor
        }
        if let split = view as? NSSplitView {
            split.wantsLayer = true
            split.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        for subview in view.subviews {
            restoreOpaqueChrome(in: subview)
        }
    }
}

/// Window-level blurred backdrop. Broad SwiftUI surfaces add the cool Codex
/// washes above this view; the desktop itself is never shown unblurred.
private final class WindowGlassBackdropView: NSView {
    private let effectView = NSVisualEffectView()
    private let mistView = NSView()
    private let overlayView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        mistView.wantsLayer = true
        mistView.layer?.backgroundColor = NSColor.clear.cgColor
        mistView.layer?.masksToBounds = true
        mistView.autoresizingMask = [.width, .height]
        addSubview(mistView)

        overlayView.wantsLayer = true
        overlayView.autoresizingMask = [.width, .height]
        addSubview(overlayView)

    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        mistView.frame = bounds
        overlayView.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshOverlay()
    }

    func apply(
        transparency: Double,
        blurStrength: WindowGlassAppearance.BlurStrength
    ) {
        effectView.material = .underWindowBackground
        mistView.layer?.backgroundFilters = [blurStrength.backgroundBlurFilter]
        overlayView.alphaValue = WindowGlassAppearance.fillOpacity(transparency: transparency)
        refreshOverlay()
    }

    private func refreshOverlay() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark
            ? NSColor(red: 0.055, green: 0.065, blue: 0.085, alpha: 1)
            : NSColor(red: 0.955, green: 0.968, blue: 0.992, alpha: 1)
        overlayView.layer?.backgroundColor = color.cgColor
    }
}

private extension WindowGlassAppearance.BlurStrength {
    var backgroundBlurFilter: CIFilter {
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(backdropBlurRadius, forKey: kCIInputRadiusKey)
        return filter
    }
}
#endif
