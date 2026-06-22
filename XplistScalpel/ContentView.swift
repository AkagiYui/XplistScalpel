//
//  ContentView.swift
//  XplistScalpel
//
//  Top-level window layout: action bar, tab strip, the editor (tree or source)
//  with an optional find bar, and the status bar. Hosts the open/save dialogs.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var app: AppModel

    private let openTypes: [UTType] = [.propertyList, .xml, .data, .item]

    var body: some View {
        VStack(spacing: 0) {
            ToolbarBar(app: app)
            Divider()

            if !app.documents.isEmpty {
                TabStrip(app: app)
                Divider()
            }

            if let doc = app.activeDocument {
                if app.showFind {
                    FindBar(doc: doc, app: app)
                    Divider()
                }
                if app.showSource {
                    SourceView(doc: doc)
                } else {
                    ColumnHeader()
                    TreeEditorView(doc: doc)
                }
                Divider()
                StatusBar(doc: doc)
            } else {
                WelcomeView(app: app)
            }
        }
        .frame(minWidth: 840, minHeight: 540)
        .fileImporter(isPresented: $app.isOpenPanelPresented,
                      allowedContentTypes: openTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    app.open(url: url)
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .fileExporter(isPresented: $app.isExportPanelPresented,
                      document: PlistExportFile(data: app.exportData),
                      contentType: .propertyList,
                      defaultFilename: app.activeDocument?.displayName ?? "Untitled") { result in
            if case .success(let url) = result { app.didExport(to: url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { app.open(url: url) }
            return !urls.isEmpty
        }
        .alert("Error", isPresented: Binding(
            get: { app.lastError != nil },
            set: { if !$0 { app.lastError = nil } }
        )) {
            Button("OK") { app.lastError = nil }
        } message: {
            Text(app.lastError ?? "")
        }
        .confirmationDialog(
            "Do you want to close this file without saving?",
            isPresented: Binding(
                get: { app.pendingCloseDocID != nil },
                set: { if !$0 { app.pendingCloseDocID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Close Without Saving", role: .destructive) {
                if let id = app.pendingCloseDocID,
                   let doc = app.documents.first(where: { $0.id == id }) {
                    app.close(doc)
                }
            }
            Button("Cancel", role: .cancel) { app.pendingCloseDocID = nil }
        } message: {
            Text("Your changes will be lost if you don't save them.")
        }
    }
}
