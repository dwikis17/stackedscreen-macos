//
//  StackedScreenshotApp.swift
//  StackedScreenshot
//

import SwiftUI

@main
struct StackedScreenshotApp: App {
    @StateObject private var store = ScreenshotStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store, shortcutManager: store.shortcutManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack")
                Text("\(store.captures.count)")
            }
            .accessibilityIdentifier("StackedScreenshotMenuBarItem")
            .accessibilityLabel("Stacked Screenshot, \(store.captures.count) screenshots stacked")
        }
        .menuBarExtraStyle(.window)
    }
}
