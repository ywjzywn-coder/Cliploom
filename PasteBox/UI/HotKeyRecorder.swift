import AppKit
import SwiftUI

struct HotKeyRecorder: NSViewRepresentable {
    let configuration: HotKeyConfiguration
    let onCapture: (HotKeyConfiguration) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        view.onCapture = onCapture
        view.displayName = configuration.displayName
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        if !nsView.isRecording {
            nsView.displayName = configuration.displayName
        }
    }
}

final class HotKeyRecorderNSView: NSView {
    var onCapture: ((HotKeyConfiguration) -> Void)?
    var displayName = "" { didSet { needsDisplay = true } }
    private(set) var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 30) }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            return
        }
        guard let configuration = HotKeyConfiguration.from(event: event) else {
            NSSound.beep()
            return
        }
        displayName = configuration.displayName
        isRecording = false
        onCapture?(configuration)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .controlBackgroundColor)
            .setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : .separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let value = isRecording ? String(localized: "hotkey.recording") : displayName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = value.size(withAttributes: attributes)
        value.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
