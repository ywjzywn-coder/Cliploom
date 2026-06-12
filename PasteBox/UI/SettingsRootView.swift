import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var controller: AppController
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        Group {
            if onboardingCompleted {
                SettingsView()
            } else {
                OnboardingView()
            }
        }
        .environmentObject(controller)
        .frame(minWidth: 640, minHeight: 520)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject private var permissionManager = AppController.shared.permissionManager
    @ObservedObject private var hotKeyManager = AppController.shared.hotKeyManager
    @ObservedObject private var launchManager = AppController.shared.launchAtLoginManager
    @State private var showClearConfirmation = false

    var body: some View {
        TabView {
            VStack(spacing: 0) {
                SettingsHeader(
                    title: "settings.general",
                    subtitle: "settings.general.subtitle"
                )
                Form {
                    Section("settings.hotkey.section") {
                        LabeledContent("settings.hotkey.label") {
                            HotKeyRecorder(
                                configuration: hotKeyManager.configuration(for: .clipboardPanel)
                            ) { value in
                                if !hotKeyManager.update(.clipboardPanel, to: value) {
                                    controller.showStatus(String(localized: "hotkey.conflict"))
                                }
                            }
                        }
                        LabeledContent("settings.hotkey.screenshot") {
                            HotKeyRecorder(
                                configuration: hotKeyManager.configuration(for: .screenshot)
                            ) { value in
                                if !hotKeyManager.update(.screenshot, to: value) {
                                    controller.showStatus(String(localized: "hotkey.conflict"))
                                }
                            }
                        }
                        Text("settings.hotkey.help")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let error = hotKeyManager.error(for: .clipboardPanel)
                            ?? hotKeyManager.error(for: .screenshot) {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("settings.startup.section") {
                        Toggle(
                            "settings.startup.toggle",
                            isOn: Binding(
                                get: { launchManager.isEnabled },
                                set: { launchManager.setEnabled($0) }
                            )
                        )
                        if let error = launchManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Section("settings.history.section") {
                        Text("settings.history.description")
                            .foregroundStyle(.secondary)
                        Button("settings.clear.button", role: .destructive) {
                            showClearConfirmation = true
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .tabItem { Label("settings.general", systemImage: "gearshape") }

            PermissionSettingsView()
                .tabItem { Label("settings.permissions", systemImage: "hand.raised") }
        }
        .alert("clear.alert.title", isPresented: $showClearConfirmation) {
            Button("action.cancel", role: .cancel) {}
            Button("action.clear", role: .destructive) { controller.clearAll() }
        } message: {
            Text("clear.alert.message")
        }
    }
}

private struct PermissionSettingsView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject private var permissionManager = AppController.shared.permissionManager
    @ObservedObject private var screenPermissionManager =
        AppController.shared.screenCapturePermissionManager

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(
                title: "settings.permissions",
                subtitle: "settings.permissions.subtitle"
            )
            Form {
                Section("permission.accessibility.title") {
                    LabeledContent {
                        Text(permissionStatus)
                            .foregroundStyle(
                                permissionManager.isAccessibilityGranted
                                    ? Color.green
                                    : Color.orange
                            )
                    } label: {
                        Label(
                            "permission.accessibility.title",
                            systemImage: permissionManager.isAccessibilityGranted
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            permissionManager.isAccessibilityGranted
                                ? Color.green
                                : Color.orange
                        )
                    }

                    Text("permission.accessibility.description")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("permission.request") {
                            permissionManager.requestAccessibilityPermission()
                        }
                        .pasteBoxPrimaryButtonStyle()

                        Button("permission.openSettings") {
                            permissionManager.openAccessibilitySettings()
                        }
                        .pasteBoxGlassButtonStyle()

                        Button {
                            permissionManager.refresh()
                        } label: {
                            Label("permission.refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("permission.screen.title") {
                    LabeledContent {
                        Text(screenPermissionStatus)
                            .foregroundStyle(screenPermissionManager.isGranted ? Color.green : Color.orange)
                    } label: {
                        Label(
                            "permission.screen.title",
                            systemImage: screenPermissionManager.isGranted
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(screenPermissionManager.isGranted ? Color.green : Color.orange)
                    }

                    Text("permission.screen.description")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("permission.request") {
                            screenPermissionManager.requestPermission()
                        }
                        .pasteBoxPrimaryButtonStyle()

                        Button("permission.openSettings") {
                            screenPermissionManager.openSettings()
                        }
                        .pasteBoxGlassButtonStyle()

                        Button {
                            screenPermissionManager.refresh()
                            controller.refreshScreenshotWarmState()
                        } label: {
                            Label("permission.refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("privacy.title") {
                    Label("privacy.localOnly", systemImage: "lock.shield")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text("privacy.description")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { permissionManager.refresh() }
        .onAppear {
            screenPermissionManager.refresh()
            controller.refreshScreenshotWarmState()
        }
        .onChange(of: screenPermissionManager.isGranted) { _, isGranted in
            if isGranted {
                controller.refreshScreenshotWarmState()
            }
        }
        .task {
            async let accessibility: Void = permissionManager.monitorUntilCancelled()
            async let screenCapture: Void = screenPermissionManager.monitorUntilCancelled()
            _ = await (accessibility, screenCapture)
        }
    }

    private var permissionStatus: String {
        String(
            localized: permissionManager.isAccessibilityGranted
                ? "permission.status.granted"
                : "permission.status.notGranted"
        )
    }

    private var screenPermissionStatus: String {
        String(
            localized: screenPermissionManager.isGranted
                ? "permission.status.granted"
                : "permission.status.notGranted"
        )
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject private var permissionManager = AppController.shared.permissionManager

    var body: some View {
        VStack(spacing: 24) {
            ApplicationIconView(size: 96)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)

            VStack(spacing: 8) {
                Text("onboarding.title")
                    .font(.largeTitle.bold())
                Text("onboarding.subtitle")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                onboardingRow(
                    symbol: "1.circle.fill",
                    title: "onboarding.step1.title",
                    description: "onboarding.step1.description"
                )
                onboardingRow(
                    symbol: "2.circle.fill",
                    title: "onboarding.step2.title",
                    description: "onboarding.step2.description"
                )
                onboardingRow(
                    symbol: "3.circle.fill",
                    title: "onboarding.step3.title",
                    description: "onboarding.step3.description"
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            }

            HStack {
                Button("permission.request") {
                    permissionManager.requestAccessibilityPermission()
                }
                .pasteBoxPrimaryButtonStyle()

                Button("permission.openSettings") {
                    permissionManager.openAccessibilitySettings()
                }
                .pasteBoxGlassButtonStyle()

                Button {
                    permissionManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("permission.refresh")

                Spacer()
                Label(
                    permissionStatus,
                    systemImage: permissionManager.isAccessibilityGranted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle"
                )
                .foregroundStyle(permissionManager.isAccessibilityGranted ? .green : .orange)
            }

            Spacer()

            HStack {
                Text("onboarding.permission.optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("onboarding.finish") {
                    controller.completeOnboarding()
                }
                .pasteBoxPrimaryButtonStyle()
            }
        }
        .padding(32)
        .onAppear { permissionManager.refresh() }
        .task { await permissionManager.monitorUntilCancelled() }
    }

    private var permissionStatus: String {
        String(
            localized: permissionManager.isAccessibilityGranted
                ? "permission.status.granted"
                : "permission.status.notGranted"
        )
    }

    private func onboardingRow(
        symbol: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            ApplicationIconView(size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }
}
