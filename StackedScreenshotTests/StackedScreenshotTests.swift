//
//  StackedScreenshotTests.swift
//  StackedScreenshotTests
//

import AppKit
import Carbon
import Testing
@testable import StackedScreenshot

@MainActor
struct StackedScreenshotTests {
    @Test func appendingCopiesEachCaptureInOrder() {
        let pasteboard = makePasteboard()
        let store = ScreenshotStore(pasteboard: pasteboard, registerHotKey: false)

        store.append(pngData: pngData)
        store.append(pngData: pngData)

        #expect(store.captures.count == 2)
        #expect(pasteboard.pasteboardItems?.count == 2)
        #expect(pasteboard.pasteboardItems?.allSatisfy { $0.types.contains(.fileURL) && $0.types.contains(.png) } == true)
        #expect(pasteboard.pasteboardItems?.first?.data(forType: .png) == pngData)

        let fileURLs = pasteboard.pasteboardItems?.compactMap { item -> URL? in
            guard let value = item.string(forType: .fileURL) else { return nil }
            return URL(string: value)
        } ?? []
        #expect(fileURLs.count == 2)
        #expect(fileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func removingCaptureRewritesOwnedPasteboard() {
        let pasteboard = makePasteboard()
        let store = ScreenshotStore(pasteboard: pasteboard, registerHotKey: false)

        store.append(pngData: pngData)
        store.append(pngData: pngData)
        let firstID = store.captures[0].id
        let lastID = store.captures[1].id

        store.remove(firstID)

        #expect(store.captures.count == 1)
        #expect(pasteboard.pasteboardItems?.count == 1)

        store.remove(lastID)

        #expect(store.captures.isEmpty)
        #expect(pasteboard.pasteboardItems?.isEmpty != false)
    }

    @Test func clearingOwnedPasteboardRemovesAllItems() {
        let pasteboard = makePasteboard()
        let store = ScreenshotStore(pasteboard: pasteboard, registerHotKey: false)

        store.append(pngData: pngData)
        store.clear()

        #expect(store.captures.isEmpty)
        #expect(pasteboard.pasteboardItems?.isEmpty != false)
    }

    @Test func clearPreservesClipboardChangedByAnotherApp() {
        let pasteboard = makePasteboard()
        let store = ScreenshotStore(pasteboard: pasteboard, registerHotKey: false)

        store.append(pngData: pngData)
        pasteboard.clearContents()
        pasteboard.setString("External clipboard", forType: .string)

        store.clear()

        #expect(store.captures.isEmpty)
        #expect(pasteboard.string(forType: .string) == "External clipboard")
        #expect(store.noticeMessage == "Clipboard changed; screenshot stack cleared.")
    }

    @Test func externalClipboardChangeDiscardsStackAndPreservesExternalContent() {
        let pasteboard = makePasteboard()
        let store = ScreenshotStore(pasteboard: pasteboard, registerHotKey: false)

        store.append(pngData: pngData)
        store.append(pngData: pngData)
        pasteboard.clearContents()
        pasteboard.setString("Copied text", forType: .string)

        store.reconcilePasteboardOwnership()

        #expect(store.captures.isEmpty)
        #expect(pasteboard.string(forType: .string) == "Copied text")
        #expect(store.noticeMessage == "Clipboard changed; screenshot stack cleared.")
    }

    @Test func nextCaptureStartsFreshStackAfterExternalClipboardChange() {
        let pasteboard = makePasteboard()
        let store = ScreenshotStore(pasteboard: pasteboard, registerHotKey: false)

        store.append(pngData: pngData)
        store.append(pngData: pngData)
        pasteboard.clearContents()
        pasteboard.setString("Copied text", forType: .string)

        store.append(pngData: pngData)

        #expect(store.captures.count == 1)
        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(pasteboard.pasteboardItems?.first?.data(forType: .png) == pngData)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func invalidDataDoesNotBecomeACapture() {
        let store = ScreenshotStore(pasteboard: makePasteboard(), registerHotKey: false)

        store.append(pngData: Data("not an image".utf8))

        #expect(store.captures.isEmpty)
    }

    @Test func fixedShortcutsUseExpectedKeysAndLabels() {
        #expect(ShortcutConfiguration.capture.keyCode == UInt32(kVK_ANSI_4))
        #expect(ShortcutConfiguration.capture.modifiers == UInt32(optionKey) | UInt32(cmdKey))
        #expect(ShortcutConfiguration.capture.displayName == "⌥⌘4")

        #expect(ShortcutConfiguration.clear.keyCode == UInt32(kVK_Delete))
        #expect(ShortcutConfiguration.clear.modifiers == UInt32(optionKey) | UInt32(cmdKey))
        #expect(ShortcutConfiguration.clear.displayName == "⌥⌘⌫")
    }

    @Test func fixedShortcutsRegisterIndependently() {
        var registered: [ShortcutConfiguration] = []
        let manager = ShortcutManager(registrationOverride: { configuration in
            registered.append(configuration)
            return true
        })

        manager.start()

        #expect(registered == [.capture, .clear])
        #expect(manager.errorMessage == nil)
    }

    @Test func failedClearRegistrationDoesNotUseFallback() {
        var registered: [ShortcutConfiguration] = []
        let manager = ShortcutManager(registrationOverride: { configuration in
            registered.append(configuration)
            return configuration == .capture
        })

        manager.start()

        #expect(registered == [.capture, .clear])
        #expect(manager.errorMessage?.contains("Clear shortcut ⌥⌘⌫") == true)
        #expect(manager.errorMessage?.contains("Capture shortcut ⌥⌘4") == false)
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("StackedScreenshotTests.\(UUID().uuidString)"))
    }

    private var pngData: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }
}
