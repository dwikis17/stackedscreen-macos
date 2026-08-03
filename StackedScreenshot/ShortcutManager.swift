//
//  ShortcutManager.swift
//  StackedScreenshot
//

import AppKit
import Carbon
import Combine

struct ShortcutConfiguration: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let capture = ShortcutConfiguration(
        keyCode: UInt32(kVK_ANSI_4),
        modifiers: UInt32(optionKey) | UInt32(cmdKey)
    )

    static let clear = ShortcutConfiguration(
        keyCode: UInt32(kVK_Delete),
        modifiers: UInt32(optionKey) | UInt32(cmdKey)
    )

    var displayName: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + (Self.keyLabels[keyCode] ?? "Key \(keyCode)")
    }

    private static let keyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_Delete): "⌫"
    ]
}

@MainActor
final class ShortcutManager: ObservableObject {
    static let captureShortcut = ShortcutConfiguration.capture
    static let clearShortcut = ShortcutConfiguration.clear

    @Published private(set) var errorMessage: String?

    private let registrationOverride: ((ShortcutConfiguration) -> Bool)?
    private let shouldRegisterHotKey: Bool
    private var captureAction: () -> Void = {}
    private var clearAction: () -> Void = {}
    private var captureHotKey: GlobalHotKey?
    private var clearHotKey: GlobalHotKey?
    private var captureRegistered = false
    private var clearRegistered = false

    init(
        registerHotKey: Bool = true,
        registrationOverride: ((ShortcutConfiguration) -> Bool)? = nil
    ) {
        self.shouldRegisterHotKey = registerHotKey
        self.registrationOverride = registrationOverride
    }

    func setActions(capture: @escaping () -> Void, clear: @escaping () -> Void) {
        captureAction = capture
        clearAction = clear
    }

    func start() {
        guard shouldRegisterHotKey else { return }

        var errors: [String] = []

        if !captureRegistered {
            if let registrationOverride {
                if registrationOverride(Self.captureShortcut) {
                    captureRegistered = true
                } else {
                    errors.append("Capture shortcut \(Self.captureShortcut.displayName) could not be registered.")
                }
            } else if let hotKey = makeCaptureHotKey() {
                captureHotKey = hotKey
                captureRegistered = true
            } else {
                errors.append("Capture shortcut \(Self.captureShortcut.displayName) could not be registered.")
            }
        }

        if !clearRegistered {
            if let registrationOverride {
                if registrationOverride(Self.clearShortcut) {
                    clearRegistered = true
                } else {
                    errors.append("Clear shortcut \(Self.clearShortcut.displayName) could not be registered.")
                }
            } else if let hotKey = makeClearHotKey() {
                clearHotKey = hotKey
                clearRegistered = true
            } else {
                errors.append("Clear shortcut \(Self.clearShortcut.displayName) could not be registered.")
            }
        }

        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func makeCaptureHotKey() -> GlobalHotKey? {
        GlobalHotKey(configuration: Self.captureShortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.captureAction()
            }
        }
    }

    private func makeClearHotKey() -> GlobalHotKey? {
        GlobalHotKey(configuration: Self.clearShortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.clearAction()
            }
        }
    }
}

private final class GlobalHotKey {
    private static var nextID: UInt32 = 1

    private let action: () -> Void
    private let eventHotKeyID: EventHotKeyID
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init?(configuration: ShortcutConfiguration, action: @escaping () -> Void) {
        self.action = action
        self.eventHotKeyID = EventHotKeyID(signature: 0x53534352, id: Self.nextID)
        Self.nextID += 1

        guard register(configuration: configuration) else {
            return nil
        }
    }

    deinit {
        unregister()
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func register(configuration: ShortcutConfiguration) -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }

            let hotKey = Unmanaged<GlobalHotKey>
                .fromOpaque(userData)
                .takeUnretainedValue()

            var pressedHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

            guard status == noErr,
                  pressedHotKeyID.signature == hotKey.eventHotKeyID.signature,
                  pressedHotKeyID.id == hotKey.eventHotKeyID.id else {
                return OSStatus(eventNotHandledErr)
            }

            hotKey.action()
            return noErr
        }

        guard InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        ) == noErr else {
            return false
        }

        guard RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        ) == noErr else {
            unregister()
            return false
        }

        return true
    }
}
