import CalendarCountdownCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ComposerMultilineField: View {
    let title: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 3...8
    var onSubmit: () -> Void

    var body: some View {
        #if os(macOS)
        LabeledContent(title) {
            MacReturnAwareTextView(
                text: $text,
                onSubmit: onSubmit
            )
            .frame(minHeight: CGFloat(lineLimit.lowerBound) * 22, maxHeight: CGFloat(lineLimit.upperBound) * 22)
        }
        #else
        TextField(title, text: $text, axis: .vertical)
            .lineLimit(lineLimit)
        #endif
    }
}

#if os(macOS)
private struct MacReturnAwareTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .exterior

        let textView = ReturnAwareNSTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = { [coordinator = context.coordinator] in
            coordinator.onSubmit()
        }
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.focusRingType = .exterior
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.textView?.onSubmit = {
            context.coordinator.onSubmit()
        }
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let clamped = NSRange(
                location: min(selected.location, textView.string.utf16.count),
                length: 0
            )
            textView.setSelectedRange(clamped)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        weak var textView: ReturnAwareNSTextView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let value = textView.string
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }
    }
}

private final class ReturnAwareNSTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event)
            return
        }
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        switch ComposerReturnAction.fromReturn(commandPressed: event.modifierFlags.contains(.command)) {
        case .insertNewline:
            insertText("\n", replacementRange: selectedRange())
        case .submit:
            onSubmit?()
        }
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(sender)
    }
}
#endif
