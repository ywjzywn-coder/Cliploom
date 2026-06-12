import SwiftData
import SwiftUI

@main
struct CliploomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: ClipboardItem.self)
        } catch {
            fatalError("Unable to create Cliploom data store: \(error)")
        }
        AppController.shared.install(container: container)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(AppController.shared)
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarLabelView: View {
    @ObservedObject private var controller = AppController.shared

    var body: some View {
        Image(systemName: controller.isPaused ? "clipboard.fill" : "clipboard")
    }
}
