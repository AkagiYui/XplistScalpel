//
//  XplistScalpelApp.swift
//  XplistScalpel
//
//  App entry point and menu-bar commands.
//

import SwiftUI

/// Handles files handed to the app outside of SwiftUI's `.onOpenURL`:
///   - command-line arguments (`XplistScalpel path/to/file.plist`)
///   - Launch Services `application(_:open:)` (double-click, `open -a`, "Open With")
/// `.onOpenURL` alone only fires for some activation paths; this delegate
/// covers the rest so the app reliably opens files passed any way.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[XS] didFinishLaunching args=\(CommandLine.arguments.dropFirst().map(\.self))")
        // Open any plist paths passed as command-line arguments.
        let args = CommandLine.arguments.dropFirst()
        for arg in args {
            let url = URL(fileURLWithPath: arg)
            if url.pathExtension.lowercased() == "plist" { app.open(url: url) }
        }
    }

    // Legacy 4-arg form — reliable for Launch Services file handoff on macOS.
    func application(_ application: NSApplication, openFiles filenames: [String]) {
        NSLog("[XS] openFiles delegate \(filenames)")
        for name in filenames {
            let url = URL(fileURLWithPath: name)
            if url.pathExtension.lowercased() == "plist" { app.open(url: url) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("[XS] application(_:open:) delegate \(urls.map(\.path))")
        for url in urls { app.open(url: url) }
    }
}

@main
struct XplistScalpelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var app: AppModel { appDelegate.app }

    var body: some Scene {
        WindowGroup {
            ContentView(app: app)
                .onOpenURL { url in app.open(url: url) }
        }
        .commands {
            AppCommands(app: app)
        }
    }
}

struct AppCommands: Commands {
    let app: AppModel

    private var doc: PlistDocument? { app.activeDocument }

    var body: some Commands {
        // File menu
        CommandGroup(replacing: .newItem) {
            Button("New") { app.newDocument() }
                .keyboardShortcut("n")
            Button("Open…") { app.requestOpen() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(app.recentFiles.indices, id: \.self) { index in
                    Button(app.recentFiles[index].lastPathComponent) { app.openRecent(at: index) }
                }
                if !app.recentFiles.isEmpty {
                    Divider()
                    Button("Clear Menu") { app.clearRecents() }
                }
            }
            Divider()
            Button("Close") { app.closeActive() }
                .keyboardShortcut("w")
                .disabled(doc == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { app.save() }
                .keyboardShortcut("s")
                .disabled(doc == nil)
            Button("Save As…") { app.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(doc == nil)
        }

        // Edit menu — replace the (disabled) default undo/redo with ours.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { doc?.undo() }
                .keyboardShortcut("z")
                .disabled(!(doc?.canUndo ?? false))
            Button("Redo") { doc?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(doc?.canRedo ?? false))
        }

        // Node menu
        CommandMenu("Node") {
            Button("Add Child") { doc?.addChild() }
                .keyboardShortcut("n", modifiers: [.option, .command])
            Button("Add Sibling") { doc?.addSibling() }
                .keyboardShortcut(.return, modifiers: .command)
            Divider()
            Button("Duplicate") { doc?.duplicateSelection() }
                .keyboardShortcut("d")
            Button("Delete") { doc?.deleteSelection() }
            Divider()
            Button("Move Up") { doc?.moveUp() }
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
            Button("Move Down") { doc?.moveDown() }
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
            Button("Sort Children") { doc?.sortChildren() }
            Divider()
            Button("Copy Node") { app.copySelection() }
                .keyboardShortcut("c", modifiers: [.option, .command])
            Button("Cut Node") { app.cutSelection() }
                .keyboardShortcut("x", modifiers: [.option, .command])
            Button("Paste Node") { app.paste() }
                .keyboardShortcut("v", modifiers: [.option, .command])
            Button("Paste as Child") { app.pasteAsChild() }
                .keyboardShortcut("v", modifiers: [.option, .command, .shift])
        }

        // Find menu
        CommandMenu("Find") {
            Button("Find…") { app.showFind = true }
                .keyboardShortcut("f")
                .disabled(doc == nil)
            Button("Find Next") { doc?.nextMatch() }
                .keyboardShortcut("g")
                .disabled(doc?.matches.isEmpty ?? true)
            Button("Find Previous") { doc?.previousMatch() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(doc?.matches.isEmpty ?? true)
        }

        // View menu additions
        CommandGroup(after: .sidebar) {
            Button("Expand All") { doc?.setExpandedAll(true) }
                .keyboardShortcut("e", modifiers: [.command, .control])
                .disabled(doc == nil)
            Button("Collapse All") { doc?.setExpandedAll(false) }
                .keyboardShortcut("r", modifiers: [.command, .control])
                .disabled(doc == nil)
            Button(app.showSource ? "Show Tree" : "Show Plist Text") {
                app.showSource.toggle()
            }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(doc == nil)
        }
    }
}
