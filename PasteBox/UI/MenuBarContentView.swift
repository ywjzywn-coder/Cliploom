import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        Button {
            controller.showPanel()
        } label: {
            Label("menu.open", systemImage: "clipboard")
        }
        .keyboardShortcut("v", modifiers: [.option])

        Button {
            controller.startScreenshot()
        } label: {
            Label("menu.screenshot", systemImage: "viewfinder")
        }
        .keyboardShortcut("a", modifiers: [.option])

        Button {
            controller.isPaused.toggle()
        } label: {
            Label(
                controller.isPaused ? "menu.resume" : "menu.pause",
                systemImage: controller.isPaused ? "record.circle" : "pause.circle"
            )
        }

        if let statusMessage = controller.statusMessage {
            Text(statusMessage)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button {
            controller.clearAll()
        } label: {
            Label("menu.clear", systemImage: "trash")
        }

        Button {
            controller.showSettings()
        } label: {
            Label("menu.settings", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("menu.quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
