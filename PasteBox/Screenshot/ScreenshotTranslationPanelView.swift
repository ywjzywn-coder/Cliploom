import AppKit
import NaturalLanguage
import SwiftUI
import Translation

@MainActor
final class ScreenshotTranslationModel: ObservableObject {
    @Published var previewImage: NSImage?
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var statusText = String(localized: "screenshot.translate.recognizing")
    @Published var isWorking = true
    @Published var configuration: TranslationSession.Configuration?

    var onRetry: (() -> Void)?
    var onCopy: ((String) -> Void)?
    var onClose: (() -> Void)?

    private var requestID = UUID()
    private var configuredTargetIdentifier: String?

    func showPreview(_ image: CGImage, displaySize: CGSize? = nil) {
        previewImage = NSImage(
            cgImage: image,
            size: displaySize ?? CGSize(
                width: image.width,
                height: image.height
            )
        )
    }

    func showRecognizing() {
        requestID = UUID()
        configuredTargetIdentifier = nil
        configuration = nil
        sourceText = ""
        translatedText = ""
        statusText = String(localized: "screenshot.translate.recognizing")
        isWorking = true
    }

    func translate(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            showMessage(String(localized: "screenshot.translate.empty"))
            return
        }

        requestID = UUID()
        sourceText = value
        translatedText = ""
        statusText = String(localized: "screenshot.translate.processing")
        isWorking = true

        let targetIdentifier = ScreenshotTranslationDirection
            .targetIdentifier(for: value)
        if configuredTargetIdentifier == targetIdentifier {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: targetIdentifier)
            )
            configuredTargetIdentifier = targetIdentifier
        }
    }

    func showMessage(_ message: String) {
        configuredTargetIdentifier = nil
        configuration = nil
        translatedText = ""
        statusText = message
        isWorking = false
    }

    func run(using session: TranslationSession) async {
        let currentRequestID = requestID
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        do {
            let response = try await session.translate(text)
            guard currentRequestID == requestID else { return }
            translatedText = response.targetText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            statusText = languageSummary(
                sourceIdentifier: response.sourceLanguage.minimalIdentifier,
                targetIdentifier: response.targetLanguage.minimalIdentifier
            )
            isWorking = false
        } catch is CancellationError {
            return
        } catch {
            guard currentRequestID == requestID else { return }
            statusText = String(localized: "screenshot.translate.failed")
            isWorking = false
        }
    }

    func copyTranslation() {
        let value = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onCopy?(value)
    }

    private func languageSummary(
        sourceIdentifier: String,
        targetIdentifier: String
    ) -> String {
        let locale = Locale.current
        let source = locale.localizedString(
            forIdentifier: sourceIdentifier
        ) ?? sourceIdentifier
        let target = locale.localizedString(
            forIdentifier: targetIdentifier
        ) ?? targetIdentifier
        return String(
            format: String(localized: "screenshot.translate.languages"),
            source,
            target
        )
    }
}

private struct ScreenshotTranslationRootView: View {
    @ObservedObject var model: ScreenshotTranslationModel

    var body: some View {
        VStack(spacing: 12) {
            header
            HSplitView {
                preview
                    .frame(minWidth: 300)
                results
                    .frame(minWidth: 320)
            }
            footer
        }
        .padding(14)
        .background(.regularMaterial)
        .translationTask(model.configuration) { session in
            await model.run(using: session)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "translate")
                .foregroundStyle(.tint)
            Text("screenshot.translate.title")
                .font(.headline)
            Spacer()
            Button {
                model.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .pasteBoxHoverButtonStyle(tint: .secondary, cornerRadius: 7)
            .help(Text("action.cancel"))
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("screenshot.ocr.preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack {
                Color.black
                if let image = model.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            textSection(
                title: String(localized: "screenshot.translate.source"),
                text: model.sourceText,
                placeholder: String(localized: "screenshot.translate.recognizing")
            )
            textSection(
                title: String(localized: "screenshot.translate.result"),
                text: model.translatedText,
                placeholder: model.statusText
            )
        }
    }

    private func textSection(
        title: String,
        text: String,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("screenshot.translate.retry") {
                model.onRetry?()
            }
            .disabled(model.isWorking)
            Button("screenshot.translate.copy") {
                model.copyTranslation()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(model.translatedText.isEmpty)
        }
    }
}

@MainActor
final class ScreenshotTranslationPanelView: NSVisualEffectView {
    var onRetry: (() -> Void)? {
        didSet { model.onRetry = onRetry }
    }
    var onCopy: ((String) -> Void)? {
        didSet { model.onCopy = onCopy }
    }
    var onClose: (() -> Void)? {
        didSet { model.onClose = onClose }
    }

    private let model = ScreenshotTranslationModel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor

        let hostingView = NSHostingView(
            rootView: ScreenshotTranslationRootView(model: model)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPreview(_ image: CGImage, displaySize: CGSize? = nil) {
        model.showPreview(image, displaySize: displaySize)
    }

    func showRecognizing() {
        model.showRecognizing()
    }

    func translate(_ text: String) {
        model.translate(text)
    }

    func showMessage(_ message: String) {
        model.showMessage(message)
    }
}
