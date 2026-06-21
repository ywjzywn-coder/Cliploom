import AppKit

private enum BarcodeMarkerKind {
    case link
    case unsupported
}

private final class BarcodeMarkerButton: NSButton {
    let result: BarcodeResult?
    let markerKind: BarcodeMarkerKind

    init(
        result: BarcodeResult?,
        kind: BarcodeMarkerKind,
        target: AnyObject?,
        action: Selector?
    ) {
        self.result = result
        markerKind = kind
        super.init(frame: .zero)

        image = NSImage(
            systemSymbolName: kind == .link ? "arrow.up.right" : "nosign",
            accessibilityDescription: String(
                localized: kind == .link
                    ? "screenshot.scan.open"
                    : "screenshot.scan.unsupported"
            )
        )
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        bezelStyle = .circular
        isBordered = false
        contentTintColor = .white
        identifier = NSUserInterfaceItemIdentifier(
            kind == .link ? "barcode.link" : "barcode.unsupported"
        )

        if kind == .link {
            self.target = target
            self.action = action
            toolTip = result?.webURL?.host()
        } else {
            isEnabled = false
            toolTip = String(localized: "screenshot.scan.unsupported")
        }

        wantsLayer = true
        layer?.backgroundColor = (
            kind == .link ? NSColor.controlAccentColor : NSColor.systemRed
        ).cgColor
        layer?.cornerRadius = 20
        layer?.borderWidth = 2.5
        layer?.borderColor = NSColor.white.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.78
        layer?.shadowRadius = 8
        layer?.shadowOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAttentionAnimation(delay: TimeInterval) {
        guard markerKind == .link,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            return
        }

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.92
        pulse.toValue = 1.13
        pulse.duration = 0.78
        pulse.beginTime = CACurrentMediaTime() + delay
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "cliploom.linkPulse")

        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = 0.38
        glow.toValue = 0.95
        glow.duration = 0.78
        glow.beginTime = CACurrentMediaTime() + delay
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(glow, forKey: "cliploom.linkGlow")
    }
}

@MainActor
private final class BarcodePreviewView: NSView {
    private final class PreviewImageView: NSImageView {
        override var intrinsicContentSize: NSSize {
            NSSize(
                width: NSView.noIntrinsicMetric,
                height: NSView.noIntrinsicMetric
            )
        }
    }

    var onOpen: ((BarcodeResult) -> Void)?

    private let imageView = PreviewImageView()
    private let dimmingView = NSView()
    private var markerButtons: [BarcodeMarkerButton] = []

    var isDimmed: Bool {
        !dimmingView.isHidden
    }

    var animatedLinkButtonCount: Int {
        markerButtons.filter {
            $0.layer?.animation(forKey: "cliploom.linkPulse") != nil
        }.count
    }

    var unsupportedMarkerCount: Int {
        markerButtons.filter { $0.markerKind == .unsupported }.count
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: NSView.noIntrinsicMetric
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        dimmingView.wantsLayer = true
        dimmingView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.48)
            .cgColor
        dimmingView.isHidden = true
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimmingView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        positionMarkerButtons()
    }

    func showImage(_ image: CGImage, displaySize: CGSize) {
        imageView.image = NSImage(
            cgImage: image,
            size: displaySize
        )
        clearResults()
    }

    func showResults(_ results: [BarcodeResult]) {
        clearResults()

        var linkIndex = 0
        for result in results {
            let kind: BarcodeMarkerKind = result.webURL == nil
                ? .unsupported
                : .link
            let button = BarcodeMarkerButton(
                result: result,
                kind: kind,
                target: self,
                action: kind == .link ? #selector(openLink(_:)) : nil
            )
            addSubview(button)
            markerButtons.append(button)
            if kind == .link {
                button.startAttentionAnimation(
                    delay: TimeInterval(linkIndex) * 0.12
                )
                linkIndex += 1
            }
        }
        dimmingView.isHidden = markerButtons.isEmpty
        positionMarkerButtons()
    }

    func showUnsupportedMarker() {
        clearResults()
        let button = BarcodeMarkerButton(
            result: nil,
            kind: .unsupported,
            target: nil,
            action: nil
        )
        addSubview(button)
        markerButtons = [button]
        dimmingView.isHidden = false
        positionMarkerButtons()
    }

    func clearResults() {
        for button in markerButtons {
            button.layer?.removeAllAnimations()
            button.removeFromSuperview()
        }
        markerButtons = []
        dimmingView.isHidden = true
    }

    private func positionMarkerButtons() {
        guard let image = imageView.image else { return }
        let imageRect = ScreenshotPreviewGeometry.aspectFitRect(
            contentSize: image.size,
            in: bounds
        )
        let buttonSize: CGFloat = 40
        let inset = buttonSize / 2

        for button in markerButtons {
            let center = button.result.map {
                ScreenshotPreviewGeometry.center(
                    of: $0.boundingBox,
                    in: imageRect
                )
            } ?? CGPoint(x: imageRect.midX, y: imageRect.midY)
            let clampedCenter = CGPoint(
                x: min(max(center.x, imageRect.minX + inset), imageRect.maxX - inset),
                y: min(max(center.y, imageRect.minY + inset), imageRect.maxY - inset)
            )
            button.frame = CGRect(
                x: clampedCenter.x - inset,
                y: clampedCenter.y - inset,
                width: buttonSize,
                height: buttonSize
            )
        }
    }

    @objc private func openLink(_ sender: BarcodeMarkerButton) {
        guard let result = sender.result else { return }
        onOpen?(result)
    }
}

@MainActor
final class ScreenshotBarcodePanelView: NSVisualEffectView {
    var onRetry: (() -> Void)?
    var onOpen: ((BarcodeResult) -> Void)?
    var onClose: (() -> Void)?

    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let previewView = BarcodePreviewView()
    private let retryButton = NSButton()

    var isPreviewDimmed: Bool {
        previewView.isDimmed
    }

    var animatedLinkButtonCount: Int {
        previewView.animatedLinkButtonCount
    }

    var unsupportedMarkerCount: Int {
        previewView.unsupportedMarkerCount
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPreview(_ image: CGImage, displaySize: CGSize? = nil) {
        previewView.showImage(
            image,
            displaySize: displaySize ?? CGSize(
                width: image.width,
                height: image.height
            )
        )
    }

    func showLoading() {
        previewView.clearResults()
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = String(localized: "screenshot.scan.processing")
        statusLabel.isHidden = false
        retryButton.isEnabled = false
    }

    func showResults(_ results: [BarcodeResult]) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        retryButton.isEnabled = true
        previewView.showResults(results)

        let linkCount = results.filter { $0.webURL != nil }.count
        if linkCount == 0 {
            statusLabel.stringValue = String(
                format: String(localized: "screenshot.scan.noLinks"),
                results.count
            )
        } else {
            statusLabel.stringValue = String(
                format: String(localized: "screenshot.scan.summary"),
                results.count,
                linkCount
            )
        }
        statusLabel.isHidden = false
    }

    func showMessage(_ message: String) {
        previewView.clearResults()
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = message
        statusLabel.isHidden = false
        retryButton.isEnabled = true
    }

    func showUnsupportedResult(_ message: String) {
        previewView.showUnsupportedMarker()
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

        previewView.onOpen = { [weak self] result in
            self?.onOpen?(result)
        }

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
            previewView,
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
            previewView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            previewView.heightAnchor.constraint(
                equalTo: content.heightAnchor,
                constant: -108
            ),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            progressIndicator.widthAnchor.constraint(equalToConstant: 14),
            progressIndicator.heightAnchor.constraint(equalToConstant: 14)
        ])

        showLoading()
    }

    @objc private func retryScan() {
        onRetry?()
    }

    @objc private func closePanel() {
        onClose?()
    }
}
