import AppKit

@MainActor
final class ScreenshotBarcodePanelView: NSVisualEffectView {
    var onRetry: (() -> Void)?
    var onCopy: ((BarcodeResult) -> Void)?
    var onOpen: ((BarcodeResult) -> Void)?
    var onClose: (() -> Void)?

    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let resultsStack = NSStackView()
    private let retryButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLoading() {
        clearResults()
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = String(localized: "screenshot.scan.processing")
        statusLabel.isHidden = false
        retryButton.isEnabled = false
    }

    func showResults(_ results: [BarcodeResult]) {
        clearResults()
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = String(
            format: String(localized: "screenshot.scan.count"),
            results.count
        )
        statusLabel.isHidden = false
        retryButton.isEnabled = true

        for result in results {
            resultsStack.addArrangedSubview(resultRow(for: result))
        }
    }

    func showMessage(_ message: String) {
        clearResults()
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = message
        statusLabel.isHidden = false
        retryButton.isEnabled = true
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

        let iconView = NSImageView()
        iconView.image = NSImage(
            systemSymbolName: "qrcode.viewfinder",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(
            labelWithString: String(localized: "screenshot.scan.title")
        )
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

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
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        let statusRow = NSStackView(views: [
            progressIndicator,
            statusLabel,
            NSView()
        ])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 7

        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 8
        resultsStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(resultsStack)

        let scrollView = NSScrollView()
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        retryButton.title = String(localized: "screenshot.scan.retry")
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryScan)

        let footer = NSStackView(views: [NSView(), retryButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let content = NSStackView(views: [
            header,
            statusRow,
            scrollView,
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
            statusRow.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            scrollView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            resultsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            resultsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            resultsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            resultsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            progressIndicator.widthAnchor.constraint(equalToConstant: 14),
            progressIndicator.heightAnchor.constraint(equalToConstant: 14)
        ])

        showLoading()
    }

    private func resultRow(for result: BarcodeResult) -> NSView {
        let typeLabel = NSTextField(labelWithString: result.symbology)
        typeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        typeLabel.textColor = .secondaryLabelColor

        let payloadLabel = NSTextField(wrappingLabelWithString: result.payload)
        payloadLabel.font = .systemFont(ofSize: 13)
        payloadLabel.isSelectable = true
        payloadLabel.maximumNumberOfLines = 4
        payloadLabel.lineBreakMode = .byTruncatingTail

        let copyButton = BarcodeResultButton(
            title: String(localized: "screenshot.scan.copy"),
            result: result,
            target: self,
            action: #selector(copyResult(_:))
        )
        copyButton.bezelStyle = .rounded

        var buttons = [copyButton as NSView]
        if result.webURL != nil {
            let openButton = BarcodeResultButton(
                title: String(localized: "screenshot.scan.open"),
                result: result,
                target: self,
                action: #selector(openResult(_:))
            )
            openButton.bezelStyle = .rounded
            buttons.append(openButton)
        }
        buttons.append(NSView())

        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let stack = NSStackView(views: [typeLabel, payloadLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 9
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.74).cgColor
        stack.layer?.borderWidth = 1
        stack.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
        payloadLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        return stack
    }

    private func clearResults() {
        for view in resultsStack.arrangedSubviews {
            resultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    @objc private func retryScan() {
        onRetry?()
    }

    @objc private func copyResult(_ sender: BarcodeResultButton) {
        onCopy?(sender.result)
    }

    @objc private func openResult(_ sender: BarcodeResultButton) {
        onOpen?(sender.result)
    }

    @objc private func closePanel() {
        onClose?()
    }
}

private final class BarcodeResultButton: NSButton {
    let result: BarcodeResult

    init(
        title: String,
        result: BarcodeResult,
        target: AnyObject?,
        action: Selector?
    ) {
        self.result = result
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
