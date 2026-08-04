//
//  ScreenshotController.swift
//  StackedScreenshot
//

import AppKit
import Combine
import CoreGraphics
import Foundation

struct ScreenshotCapture: Identifiable {
    let id: UUID
    let pngData: Data

    init(id: UUID = UUID(), pngData: Data) {
        self.id = id
        self.pngData = pngData
    }

    var image: NSImage? {
        NSImage(data: pngData)
    }
}

enum ScreenRecordingStatus: Equatable {
    case ready
    case permissionRequired
}

@MainActor
final class ScreenshotStore: ObservableObject {
    @Published private(set) var captures: [ScreenshotCapture] = []
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var screenRecordingStatus: ScreenRecordingStatus

    let shortcutManager: ShortcutManager

    private let pasteboard: NSPasteboard
    private var lastPasteboardChangeCount: Int?
    private var captureProcess: Process?
    private var didRequestScreenRecordingPermission = false
    private var noticeDismissTask: Task<Void, Never>?
    private var pasteboardFileDirectory: URL?

    init(
        pasteboard: NSPasteboard = .general,
        registerHotKey: Bool = true
    ) {
        self.pasteboard = pasteboard
        self.screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .ready : .permissionRequired
        self.shortcutManager = ShortcutManager(registerHotKey: registerHotKey)

        shortcutManager.setActions(
            capture: { [weak self] in
                self?.startCapture()
            },
            clear: { [weak self] in
                self?.clear()
            }
        )

        if registerHotKey {
            shortcutManager.start()
        }
    }

    func refreshScreenRecordingStatus() {
        screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .ready : .permissionRequired
    }

    func startCapture() {
        reconcilePasteboardOwnership()
        guard !isCapturing else { return }

        errorMessage = nil
        refreshScreenRecordingStatus()

        guard screenRecordingStatus == .ready else {
            if !didRequestScreenRecordingPermission {
                didRequestScreenRecordingPermission = true
                _ = CGRequestScreenCaptureAccess()
            }
            refreshScreenRecordingStatus()
            errorMessage = "Allow Screen Recording to capture a region."
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stacked-screenshot-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-t", "png", outputURL.path]
        captureProcess = process
        isCapturing = true

        process.terminationHandler = { [weak self] process in
            let data = try? Data(contentsOf: outputURL)
            let succeeded = process.terminationStatus == 0 && data?.isEmpty == false

            Task { @MainActor [weak self] in
                defer {
                    try? FileManager.default.removeItem(at: outputURL)
                    self?.captureProcess = nil
                    self?.isCapturing = false
                }

                guard let self, succeeded, let data else {
                    return
                }

                self.append(pngData: data)
            }
        }

        do {
            try process.run()
        } catch {
            captureProcess = nil
            isCapturing = false
            try? FileManager.default.removeItem(at: outputURL)
            errorMessage = "Could not start the screenshot tool."
        }
    }

    func append(pngData: Data) {
        reconcilePasteboardOwnership()

        guard NSImage(data: pngData) != nil else {
            errorMessage = "The screenshot could not be read."
            return
        }

        errorMessage = nil
        captures.append(ScreenshotCapture(pngData: pngData))
        writeCurrentStackToPasteboard()
    }

    func remove(_ id: UUID) {
        reconcilePasteboardOwnership()
        captures.removeAll { $0.id == id }
        refreshPasteboardIfOwned()
    }

    func clear() {
        reconcilePasteboardOwnership()
        captures.removeAll()
        clearPasteboardIfOwned()
    }

    func reconcilePasteboardOwnership() {
        guard let lastPasteboardChangeCount,
              pasteboard.changeCount != lastPasteboardChangeCount else {
            return
        }

        captures.removeAll()
        self.lastPasteboardChangeCount = nil
        cleanupPasteboardFiles()
        showClipboardNotice()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func refreshPasteboardIfOwned() {
        guard let lastPasteboardChangeCount,
              pasteboard.changeCount == lastPasteboardChangeCount else {
            return
        }

        writeCurrentStackToPasteboard()
    }

    private func clearPasteboardIfOwned() {
        guard let lastPasteboardChangeCount,
              pasteboard.changeCount == lastPasteboardChangeCount else {
            lastPasteboardChangeCount = nil
            cleanupPasteboardFiles()
            return
        }

        pasteboard.clearContents()
        self.lastPasteboardChangeCount = pasteboard.changeCount
        cleanupPasteboardFiles()
    }

    private func writeCurrentStackToPasteboard() {
        pasteboard.clearContents()
        cleanupPasteboardFiles()

        guard !captures.isEmpty else {
            lastPasteboardChangeCount = pasteboard.changeCount
            return
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-stack-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let items = try captures.enumerated().map { index, capture in
                let fileURL = directory.appendingPathComponent("screenshot-\(index + 1).png")
                try capture.pngData.write(to: fileURL, options: .atomic)

                let item = NSPasteboardItem()
                item.setString(fileURL.absoluteString, forType: .fileURL)
                item.setData(capture.pngData, forType: .png)
                return item
            }

            guard pasteboard.writeObjects(items) else {
                try? FileManager.default.removeItem(at: directory)
                errorMessage = "The screenshots could not be copied to the clipboard."
                lastPasteboardChangeCount = nil
                return
            }

            pasteboardFileDirectory = directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            errorMessage = "The screenshots could not be copied to the clipboard."
            lastPasteboardChangeCount = nil
            return
        }

        lastPasteboardChangeCount = pasteboard.changeCount
    }

    private func cleanupPasteboardFiles() {
        guard let pasteboardFileDirectory else { return }

        try? FileManager.default.removeItem(at: pasteboardFileDirectory)
        self.pasteboardFileDirectory = nil
    }

    private func showClipboardNotice() {
        noticeDismissTask?.cancel()
        noticeMessage = "Clipboard changed; screenshot stack cleared."
        noticeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.noticeMessage = nil
            self?.noticeDismissTask = nil
        }
    }
}
