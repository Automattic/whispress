import AppKit
import SwiftUI

struct AgentComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var height: CGFloat

    let fontSize: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let isDisabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AgentComposerScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.masksToBounds = true
        scrollView.contentHeightDidChange = { [weak coordinator = context.coordinator] contentHeight in
            coordinator?.updateHeight(contentHeight: contentHeight)
        }

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.font = .systemFont(ofSize: fontSize)
        textView.isEditable = !isDisabled
        textView.isSelectable = true
        (scrollView as? AgentComposerScrollView)?.updateDocumentLayout()

        if isDisabled,
           textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        } else if isFocused,
                  textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentComposerTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(_ parent: AgentComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.isFocused = true
            parent.text = textView.string
            (scrollView as? AgentComposerScrollView)?.updateDocumentLayout()
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return false
            }

            parent.onSubmit()
            return true
        }

        func updateHeight(contentHeight: CGFloat) {
            let nextHeight = min(max(contentHeight, parent.minimumHeight), parent.maximumHeight)
            let shouldScroll = contentHeight > parent.maximumHeight + 0.5

            if scrollView?.hasVerticalScroller != shouldScroll {
                scrollView?.hasVerticalScroller = shouldScroll
            }

            guard abs(parent.height - nextHeight) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if abs(self.parent.height - nextHeight) > 0.5 {
                    self.parent.height = nextHeight
                }
            }
        }
    }
}

private final class AgentComposerScrollView: NSScrollView {
    var contentHeightDidChange: ((CGFloat) -> Void)?

    override func layout() {
        super.layout()
        updateDocumentLayout()
    }

    func updateDocumentLayout() {
        guard let textView = documentView as? NSTextView else { return }
        let contentSize = contentView.bounds.size
        let documentWidth = max(contentSize.width, 1)
        let contentHeight = Self.contentHeight(for: textView, width: documentWidth)
        let documentHeight = max(contentHeight, contentSize.height)
        let targetSize = NSSize(width: documentWidth, height: documentHeight)

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: documentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )

        if abs(textView.frame.width - targetSize.width) > 0.5
            || abs(textView.frame.height - targetSize.height) > 0.5 {
            textView.setFrameSize(targetSize)
        }

        contentHeightDidChange?(contentHeight)
    }

    private static func contentHeight(for textView: NSTextView, width: CGFloat) -> CGFloat {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return textView.textContainerInset.height * 2
        }

        textContainer.containerSize = NSSize(
            width: max(width, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return ceil(usedRect.height + (textView.textContainerInset.height * 2))
    }
}
