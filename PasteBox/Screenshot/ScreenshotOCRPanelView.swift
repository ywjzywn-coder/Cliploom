import AppKit

private final class ScaledPreviewImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: NSView.noIntrinsicMetric
        )
    }
}

private final class RememberingSplitView: NSSplitView, NSSplitViewDelegate {
    private static let fractionKey = "screenshot.ocr.previewFraction"
    private static let defaultFraction: CGFloat = 0.68
    private static let minimumFraction: CGFloat = 0.35
    private static let maximumFraction: CGFloat = 0.78

    private var hasRestoredFraction = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isVertical = true
        dividerStyle = .thin
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard !hasRestoredFraction, subviews.count == 2, bounds.width > 0 else {
            return
        }
        hasRestoredFraction = true
        let stored = UserDefaults.standard.object(forKey: Self.fractionKey) as? Double
        let fraction = Self.clampedFraction(
            CGFloat(stored ?? Double(Self.defaultFraction))
        )
        setPosition(usableWidth * fraction, ofDividerAt: 0)
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        min(
            max(proposedPosition, usableWidth * Self.minimumFraction),
            usableWidth * Self.maximumFraction
        )
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard hasRestoredFraction, subviews.count == 2, usableWidth > 0 else {
            return
        }
        let fraction = Self.clampedFraction(subviews[0].frame.width / usableWidth)
        UserDefaults.standard.set(Double(fraction), forKey: Self.fractionKey)
    }

    private var usableWidth: CGFloat {
        max(bounds.width - dividerThickness, 1)
    }

    private static func clampedFraction(_ fraction: CGFloat) -> CGFloat {
        min(max(fraction, minimumFraction), maximumFraction)
    }
}

@MainActor
final class ScreenshotOCRPanelView: NSVisualEffectView, NSTextViewDelegate {
    var onRetry: (() -> Void)?
    var onCopy: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let previewImageView = ScaledPreviewImageView()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton()
    private let copyButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLoading() {
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = String(localized: "screenshot.ocr.processing")
        statusLabel.isHidden = false
        textView.isEditable = false
        retryButton.isEnabled = false
        copyButton.isEnabled = false
    }

    func showPreview(_ image: CGImage) {
        previewImageView.image = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    func showResult(_ text: String) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.isHidden = true
        textView.string = text
        textView.isEditable = true
        retryButton.isEnabled = true
        copyButton.isEnabled = !trimmedText.isEmpty
        updateCount()
        window?.makeFirstResponder(textView)
    }

    func showMessage(_ message: String) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = message
        statusLabel.isHidden = false
        textView.isEditable = true
        retryButton.isEnabled = true
        copyButton.isEnabled = !trimmedText.isEmpty
        updateCount()
    }

    func textDidChange(_ notification: Notification) {
        copyButton.isEnabled = !trimmedText.isEmpty
        updateCount()
    }

    private var trimmedText: String {
        textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func configureView() {
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor

        let titleLabel = NSTextField(
            labelWithString: String(localized: "screenshot.ocr.title")
        )
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        let iconView = NSImageView()
        iconView.image = NSImage(
            systemSymbolName: "text.viewfinder",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(
            image: NSImage(
                systemSymbolName: "xmark",
                accessibilityDescription: String(localized: "action.cancel")
            ) ?? NSImage(),
            target: self,
            action: #selector(closePanel)
        )
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor

        let header = NSStackView(views: [
            iconView,
            titleLabel,
            NSView(),
            closeButton
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        let statusRow = NSStackView(views: [progressIndicator, statusLabel, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 7

        textView.delegate = self
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor.withAlphaComponent(0.72)
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor.separatorColor.cgColor

        let previewTitle = NSTextField(
            labelWithString: String(localized: "screenshot.ocr.preview")
        )
        previewTitle.font = .systemFont(ofSize: 12, weight: .medium)
        previewTitle.textColor = .secondaryLabelColor

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.black.cgColor
        previewImageView.layer?.cornerRadius = 8
        previewImageView.layer?.borderWidth = 1
        previewImageView.layer?.borderColor = NSColor.separatorColor.cgColor

        let previewColumn = NSStackView(views: [previewTitle, previewImageView])
        previewColumn.orientation = .vertical
        previewColumn.alignment = .leading
        previewColumn.spacing = 8

        let resultTitle = NSTextField(
            labelWithString: String(localized: "screenshot.ocr.result")
        )
        resultTitle.font = .systemFont(ofSize: 12, weight: .medium)
        resultTitle.textColor = .secondaryLabelColor

        let resultColumn = NSStackView(views: [
            resultTitle,
            statusRow,
            scrollView
        ])
        resultColumn.orientation = .vertical
        resultColumn.alignment = .leading
        resultColumn.spacing = 8

        let body = RememberingSplitView()
        body.addArrangedSubview(previewColumn)
        body.addArrangedSubview(resultColumn)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right

        retryButton.title = String(localized: "screenshot.ocr.retry")
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryRecognition)

        copyButton.title = String(localized: "screenshot.ocr.copy")
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.target = self
        copyButton.action = #selector(copyText)

        let footer = NSStackView(views: [
            countLabel,
            NSView(),
            retryButton,
            copyButton
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let content = NSStackView(views: [
            header,
            body,
            footer
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            body.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 340),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            previewImageView.widthAnchor.constraint(equalTo: previewColumn.widthAnchor),
            previewImageView.heightAnchor.constraint(equalTo: body.heightAnchor, constant: -20),
            previewColumn.heightAnchor.constraint(equalTo: body.heightAnchor),
            resultColumn.heightAnchor.constraint(equalTo: body.heightAnchor),
            statusRow.widthAnchor.constraint(equalTo: resultColumn.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: resultColumn.widthAnchor),
            scrollView.heightAnchor.constraint(equalTo: resultColumn.heightAnchor, constant: -28),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            progressIndicator.widthAnchor.constraint(equalToConstant: 14),
            progressIndicator.heightAnchor.constraint(equalToConstant: 14)
        ])

        showLoading()
    }

    private func updateCount() {
        countLabel.stringValue = String(
            format: String(localized: "screenshot.ocr.count"),
            textView.string.count
        )
    }

    @objc private func retryRecognition() {
        onRetry?()
    }

    @objc private func copyText() {
        let value = trimmedText
        guard !value.isEmpty else { return }
        onCopy?(value)
    }

    @objc private func closePanel() {
        onClose?()
    }
}
