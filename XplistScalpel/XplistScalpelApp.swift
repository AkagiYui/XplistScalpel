//
//  XplistScalpelApp.swift
//  XplistScalpel
//
//  App entry point and menu-bar commands.
//

import SwiftUI

@main
struct XplistScalpelApp: App {
    @State private var app = AppModel()

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
                ForEach(app.recentFiles, id: \.self) { url in
                    Button(url.lastPathComponent) { app.open(url: url) }
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
