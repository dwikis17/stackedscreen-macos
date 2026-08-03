//
//  ContentView.swift
//  StackedScreenshot
//

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ScreenshotStore
    @ObservedObject var shortcutManager: ShortcutManager

    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stacked Screenshot")
                        .font(.headline)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "rectangle.stack")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }

            Button {
                store.startCapture()
            } label: {
                Label("Capture Now", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isCapturing)

            permissionRow
            shortcutRow

            if store.captures.isEmpty {
                emptyState
            } else {
                captureGrid
            }

            if store.isCapturing {
                Label("Select a region…", systemImage: "viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let noticeMessage = store.noticeMessage {
                Label(noticeMessage, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if let errorMessage = shortcutManager.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            Divider()

            HStack {
                Button("Clear Stack", role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .disabled(store.captures.isEmpty)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            store.refreshScreenRecordingStatus()
            store.reconcilePasteboardOwnership()
        }
        .alert(
            "Clear \(store.captures.count) screenshots?",
            isPresented: $isClearConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                store.clear()
            }
        } message: {
            Text("This removes the current stack and its clipboard items if Stacked Screenshot still owns the clipboard.")
        }
    }

    private var statusText: String {
        switch store.captures.count {
        case 0:
            return "Press \(ShortcutManager.captureShortcut.displayName) or Capture Now"
        case 1:
            return "1 screenshot ready to paste"
        default:
            return "\(store.captures.count) screenshots ready to paste"
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 8) {
            switch store.screenRecordingStatus {
            case .ready:
                Label("Screen Recording Ready", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            case .permissionRequired:
                Label("Screen Recording Permission Needed", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)

                Spacer()

                Button("Open Settings") {
                    store.openScreenRecordingSettings()
                }
                .buttonStyle(.link)
            }
        }
        .font(.caption)
    }

    private var shortcutRow: some View {
        Label(
            "Capture \(ShortcutManager.captureShortcut.displayName) · Clear \(ShortcutManager.clearShortcut.displayName)",
            systemImage: "keyboard"
        )
        .font(.subheadline)
        .accessibilityIdentifier("FixedShortcuts")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.dashed.and.paperclip")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Your captures will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var captureGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(store.captures.enumerated()), id: \.element.id) { index, capture in
                    CaptureThumbnail(number: index + 1, capture: capture) {
                        store.remove(capture.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 300)
    }
}

private struct CaptureThumbnail: View {
    let number: Int
    let capture: ScreenshotCapture
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image = capture.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 130)
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: Circle())
                .padding(6)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove screenshot \(number)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screenshot \(number)")
    }
}
