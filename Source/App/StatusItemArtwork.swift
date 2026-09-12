#if os(macOS)
import AppKit
import CalendarCountdownCore

enum StatusItemArtwork {
    static var countdownIcon: NSImage? {
        NSImage(
            systemSymbolName: "calendar.badge.clock",
            accessibilityDescription: AppLocalization.text("nav.countdown", defaultValue: "倒数日")
        )
    }

    static var todayTasksIcon: NSImage? {
        NSImage(
            systemSymbolName: "checkmark.circle",
            accessibilityDescription: AppLocalization.text("nav.tasks", defaultValue: "任务清单")
        )
    }

    static func missionProgress(
        progress: Double?,
        side: CGFloat = CGFloat(StatusBarMissionArtworkSpec.menuBarDefaultSide)
    ) -> NSImage {
        let spec = StatusBarMissionArtworkSpec.make(progress: progress, side: Double(side))
        let image = NSImage(size: NSSize(width: spec.side, height: spec.side), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            switch spec.style {
            case .waterOrb:
                drawWaterOrb(spec: spec, in: rect)
            case .progressRing:
                drawProgressRing(spec: spec, in: rect)
            }
            return true
        }
        image.isTemplate = spec.usesTemplateRendering
        return image
    }

    private static func drawWaterOrb(spec: StatusBarMissionArtworkSpec, in rect: NSRect) {
        let inset = CGFloat(spec.contentInset)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let container = NSBezierPath(ovalIn: bounds)
        NSGraphicsContext.saveGraphicsState()
        container.addClip()
        NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: bounds.height * CGFloat(spec.fillRatio)
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
        container.lineWidth = CGFloat(spec.lineWidth)
        container.stroke()
    }

    private static func drawProgressRing(spec: StatusBarMissionArtworkSpec, in rect: NSRect) {
        let inset = CGFloat(spec.contentInset)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        let track = NSBezierPath()
        track.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360
        )
        track.lineWidth = CGFloat(spec.lineWidth)
        track.lineCapStyle = .round
        NSColor.black.withAlphaComponent(0.28).setStroke()
        track.stroke()

        guard spec.fillRatio > 0 else { return }
        let sweep = CGFloat(spec.ringSweepDegrees)
        let progress = NSBezierPath()
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - sweep,
            clockwise: true
        )
        progress.lineWidth = CGFloat(spec.lineWidth)
        progress.lineCapStyle = .round
        NSColor.black.setStroke()
        progress.stroke()
    }
}
#endif
