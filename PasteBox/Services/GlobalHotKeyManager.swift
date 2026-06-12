import AppKit
import Carbon
import Foundation

enum HotKeyAction: UInt32, CaseIterable {
    case clipboardPanel = 1
    case screenshot = 2

    var defaultsPrefix: String {
        switch self {
        case .clipboardPanel: "hotKey"
        case .screenshot: "screenshotHotKey"
        }
    }

    var defaultConfiguration: HotKeyConfiguration {
        switch self {
        case .clipboardPanel:
            HotKeyConfiguration(
                keyCode: UInt32(kVK_ANSI_V),
                modifiers: UInt32(optionKey),
                keyLabel: "V"
            )
        case .screenshot:
            HotKeyConfiguration(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(optionKey),
                keyLabel: "A"
            )
        }
    }
}

struct HotKeyConfiguration: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    static let defaultValue = HotKeyAction.clipboardPanel.defaultConfiguration

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel.uppercased()
    }

    static func from(event: NSEvent) -> HotKeyConfiguration? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        guard carbonModifiers != 0,
              let characters = event.charactersIgnoringModifiers,
              let first = characters.first,
              !first.isWhitespace
        else {
            return nil
        }
        return HotKeyConfiguration(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers,
            keyLabel: String(first).uppercased()
        )
    }
}

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    @Published private(set) var configurations: [HotKeyAction: HotKeyConfiguration] = [:]
    @Published private(set) var registrationErrors: [HotKeyAction: String] = [:]

    var configuration: HotKeyConfiguration {
        configuration(for: .clipboardPanel)
    }

    var registrationError: String? {
        registrationErrors[.clipboardPanel]
    }

    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var actions: [HotKeyAction: () -> Void] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in HotKeyAction.allCases {
            configurations[action] = Self.loadConfiguration(for: action, defaults: defaults)
        }
    }

    deinit {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func configuration(for action: HotKeyAction) -> HotKeyConfiguration {
        configurations[action] ?? action.defaultConfiguration
    }

    func error(for action: HotKeyAction) -> String? {
        registrationErrors[action]
    }

    func conflictsInternally(
        _ newConfiguration: HotKeyConfiguration,
        excluding action: HotKeyAction
    ) -> Bool {
        HotKeyAction.allCases.contains {
            $0 != action && configuration(for: $0) == newConfiguration
        }
    }

    func register(action: @escaping () -> Void) {
        register(.clipboardPanel, action: action)
    }

    func register(_ hotKeyAction: HotKeyAction, action: @escaping () -> Void) {
        actions[hotKeyAction] = action
        installEventHandlerIfNeeded()
        let status = registerReference(
            configuration(for: hotKeyAction),
            action: hotKeyAction
        )
        if status != noErr {
            registrationErrors[hotKeyAction] = String(localized: "hotkey.conflict")
        }
    }

    @discardableResult
    func update(to newConfiguration: HotKeyConfiguration) -> Bool {
        update(.clipboardPanel, to: newConfiguration)
    }

    @discardableResult
    func update(
        _ hotKeyAction: HotKeyAction,
        to newConfiguration: HotKeyConfiguration
    ) -> Bool {
        if conflictsInternally(newConfiguration, excluding: hotKeyAction) {
            registrationErrors[hotKeyAction] = String(localized: "hotkey.conflict")
            return false
        }

        let oldConfiguration = configuration(for: hotKeyAction)
        unregister(hotKeyAction)
        let status = registerReference(newConfiguration, action: hotKeyAction)
        guard status == noErr else {
            _ = registerReference(oldConfiguration, action: hotKeyAction)
            registrationErrors[hotKeyAction] = String(localized: "hotkey.conflict")
            return false
        }

        configurations[hotKeyAction] = newConfiguration
        registrationErrors[hotKeyAction] = nil
        let prefix = hotKeyAction.defaultsPrefix
        defaults.set(newConfiguration.keyCode, forKey: "\(prefix).keyCode")
        defaults.set(newConfiguration.modifiers, forKey: "\(prefix).modifiers")
        defaults.set(newConfiguration.keyLabel, forKey: "\(prefix).keyLabel")
        return true
    }

    private static func loadConfiguration(
        for action: HotKeyAction,
        defaults: UserDefaults
    ) -> HotKeyConfiguration {
        let prefix = action.defaultsPrefix
        let keyCode = defaults.object(forKey: "\(prefix).keyCode") as? NSNumber
        let modifiers = defaults.object(forKey: "\(prefix).modifiers") as? NSNumber
        let keyLabel = defaults.string(forKey: "\(prefix).keyLabel")
        guard let keyCode, let modifiers, let keyLabel else {
            return action.defaultConfiguration
        }
        return HotKeyConfiguration(
            keyCode: keyCode.uint32Value,
            modifiers: modifiers.uint32Value,
            keyLabel: keyLabel
        )
    }

    private func unregister(_ action: HotKeyAction) {
        guard let reference = hotKeyRefs.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(reference)
    }

    private func registerReference(
        _ configuration: HotKeyConfiguration,
        action: HotKeyAction
    ) -> OSStatus {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x50425831, id: action.rawValue)
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeyRefs[action] = reference
        }
        return status
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      let action = HotKeyAction(rawValue: identifier.id)
                else { return noErr }

                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    manager.actions[action]?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}
