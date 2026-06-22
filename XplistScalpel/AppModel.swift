//
//  AppModel.swift
//  XplistScalpel
//
//  Top-level application state: the set of open documents (tabs), the active
//  one, a shared node clipboard (so copy/paste works across tabs), recent
//  files, and the plumbing that drives the open/save file dialogs.
//

import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
final class AppModel {

    var documents: [PlistDocument] = []
    var activeDocumentID: UUID?

    var clipboard: [PlistNode] = []
    var showSource = false
    var showFind = false

    var recentFiles: [URL] = []
    var lastError: String?

    // File-dialog triggers observed by ContentView.
    var isOpenPanelPresented = false
    var isExportPanelPresented = false
    var exportData = Data()
    /// Document the next export should re-bind to (for Save As).
    @ObservationIgnored var exportTargetID: UUID?

    /// Document pending a close confirmation because it has unsaved changes.
    var pendingCloseDocID: UUID?

    private let recentsKey = "RecentFiles"
    private let maxRecents = 12

    var activeDocument: PlistDocument? {
        documents.first { $0.id == activeDocumentID }
    }

    init() {
        loadRecents()
    }

    // MARK: - Document lifecycle

    func newDocument() {
        let doc = PlistDocument.newDocument()
        documents.append(doc)
        activeDocumentID = doc.id
        showSource = false
    }

    func open(url: URL) {
        if let existing = documents.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            activeDocumentID = existing.id
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let (root, format) = try PlistEngine.load(data: data)
            let doc = PlistDocument(root: root, fileURL: url, format: format)
            documents.append(doc)
            activeDocumentID = doc.id
            showSource = false
            addRecent(url)
        } catch {
            lastError = "Couldn't open \(url.lastPathComponent):\n\(error.localizedDescription)"
        }
    }

    /// Attempts to close a document, prompting first if it has unsaved edits.
    func requestClose(_ doc: PlistDocument) {
        if doc.isDirty {
            pendingCloseDocID = doc.id
        } else {
            close(doc)
        }
    }

    func close(_ doc: PlistDocument) {
        guard let index = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        documents.remove(at: index)
        if activeDocumentID == doc.id {
            let newIndex = min(index, documents.count - 1)
            activeDocumentID = documents.indices.contains(newIndex) ? documents[newIndex].id : nil
        }
        pendingCloseDocID = nil
    }

    func closeActive() {
        if let doc = activeDocument { requestClose(doc) }
    }

    // MARK: - Saving

    func requestOpen() { isOpenPanelPresented = true }

    func save(_ doc: PlistDocument? = nil) {
        guard let doc = doc ?? activeDocument else { return }
        if let url = doc.fileURL {
            write(doc, to: url)
        } else {
            requestExport(doc)
        }
    }

    func saveAs(_ doc: PlistDocument? = nil) {
        guard let doc = doc ?? activeDocument else { return }
        requestExport(doc)
    }

    private func requestExport(_ doc: PlistDocument) {
        do {
            exportData = try PlistEngine.data(from: doc.root, format: doc.format)
            exportTargetID = doc.id
            isExportPanelPresented = true
        } catch {
            lastError = "Couldn't prepare file:\n\(error.localizedDescription)"
        }
    }

    /// Completion handler for the Save As exporter.
    func didExport(to url: URL) {
        guard let id = exportTargetID, let doc = documents.first(where: { $0.id == id }) else { return }
        doc.fileURL = url
        doc.isDirty = false
        addRecent(url)
        exportTargetID = nil
    }

    private func write(_ doc: PlistDocument, to url: URL) {
        do {
            let data = try PlistEngine.data(from: doc.root, format: doc.format)
            try data.write(to: url, options: .atomic)
            doc.isDirty = false
            addRecent(url)
        } catch {
            lastError = "Couldn't save \(url.lastPathComponent):\n\(error.localizedDescription)"
        }
    }

    // MARK: - Clipboard (node-level, shared across tabs)

    func copySelection() {
        guard let doc = activeDocument else { return }
        let nodes = doc.selectedNodesInOrder
        guard !nodes.isEmpty else { return }
        clipboard = nodes.map { $0.deepCopy() }
    }

    func cutSelection() {
        guard let doc = activeDocument else { return }
        copySelection()
        doc.deleteSelection()
    }

    func paste() {
        guard let doc = activeDocument, !clipboard.isEmpty else { return }
        doc.insert(clipboard.map { $0.deepCopy() }, mode: .siblingAfter)
    }

    func pasteAsChild() {
        guard let doc = activeDocument, !clipboard.isEmpty else { return }
        doc.insert(clipboard.map { $0.deepCopy() }, mode: .child)
    }

    // MARK: - Find

    func toggleFind() {
        showFind.toggle()
        if !showFind { activeDocument?.searchQuery = ""; activeDocument?.runSearch() }
    }

    // MARK: - Recent files

    private func loadRecents() {
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        recentFiles = paths.map { URL(fileURLWithPath: $0) }
    }

    private func addRecent(_ url: URL) {
        recentFiles.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > maxRecents { recentFiles = Array(recentFiles.prefix(maxRecents)) }
        UserDefaults.standard.set(recentFiles.map { $0.path }, forKey: recentsKey)
    }

    func clearRecents() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }
}
