import CoreGraphics
import Foundation

/// Shared chrome metrics for the mission create/edit inspector.
///
/// The sheet must stay inside the visible work area. Title, the first field,
/// and Cancel/Save stay in reserved chrome; the remaining fields scroll.
public enum MissionEditorLayout: Sendable {
    public static let minWidth: CGFloat = 420
    public static let idealWidth: CGFloat = 560
    public static let maxWidth: CGFloat = 640
    public static let minHeight: CGFloat = 420
    public static let idealHeight: CGFloat = 620
    public static let maxHeight: CGFloat = 720
    public static let chromeMargin: CGFloat = 48
    public static let horizontalInset: CGFloat = 20
    public static let verticalInset: CGFloat = 16
    public static let sectionSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 14
    public static let cardCornerRadius: CGFloat = 12
    public static let iconPickerMaxHeight: CGFloat = 168
    public static let footerHeight: CGFloat = 56
    public static let headerHeight: CGFloat = 52

    public static func fittingSize(available: CGSize) -> CGSize {
        let maxWidthInWorkArea = max(0, available.width - chromeMargin * 2)
        let maxHeightInWorkArea = max(0, available.height - chromeMargin * 2)
        return CGSize(
            width: clampedDimension(
                ideal: idealWidth,
                minimum: minWidth,
                maximum: maxWidth,
                available: maxWidthInWorkArea
            ),
            height: clampedDimension(
                ideal: idealHeight,
                minimum: minHeight,
                maximum: maxHeight,
                available: maxHeightInWorkArea
            )
        )
    }

    public static func contentScrollHeight(windowHeight: CGFloat) -> CGFloat {
        max(120, windowHeight - headerHeight - footerHeight)
    }

    public static var minimumReadableContentWidth: CGFloat {
        horizontalInset * 2 + 160
    }

    private static func clampedDimension(
        ideal: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        available: CGFloat
    ) -> CGFloat {
        guard available > 0 else { return minimum }
        let preferred = min(maximum, max(minimum, ideal))
        if available >= preferred { return preferred }
        return min(preferred, available)
    }
}
