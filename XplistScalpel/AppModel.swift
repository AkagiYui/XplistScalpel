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

    /// Brings the single main window back on screen. The scene installs this
    /// once a window exists (see `ContentView`); it lets non-view code — the
    /// app delegate's file-open handlers and the File-menu commands — reopen
    /// the window after the user has closed it, so opening or creating a file
    /// is never a no-op against a window-less app.
    @ObservationIgnored var showMainWindow: (() -> Void)?

    // File-dialog triggers observed by ContentView.
    var isOpenPanelPresented = false
    var isExportPanelPresented = false
    var exportData = Data()
    /// Document the next export should re-bind to (for Save As).
    @ObservationIgnored var exportTargetID: UUID?

    /// Document pending a close confirmation because it has unsaved changes.
    var pendingCloseDocID: UUID?

    /// Security-scoped bookmarks backing `recentFiles`, persisted across
    /// launches so recently-opened files can be reopened under App Sandbox.
    @ObservationIgnored private var recentBookmarks: [Data] = []
    private let bookmarksKey = "RecentBookmarks"
    private let maxRecents = 12

    var activeDocument: PlistDocument? {
        documents.first { $0.id == activeDocumentID }
    }

    init() {
        loadRecents()
    }

    // MARK: - Document lifecycle

    func newDocument() {
        showMainWindow?()
        let doc = PlistDocument.newDocument()
        documents.append(doc)
        activeDocumentID = doc.id
        showSource = false
    }

    func open(url: URL) {
        showMainWindow?()
        NSLog("[XS] open url=\(url.path) isFileURL=\(url.isFileURL) scopedGrant=start")
        if let existing = documents.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            activeDocumentID = existing.id
            return
        }
        // Under App Sandbox the URL arrives with a security scope (from the
        // open panel, drag-drop, Launch Services, or a resolved bookmark).
        // Start accessing it now and keep the grant alive for the document's
        // lifetime so later saves back to the same file succeed.
        let scoped = url.startAccessingSecurityScopedResource()
        NSLog("[XS] startAccessing returned \(scoped)")
        do {
            let data = try Data(contentsOf: url)
            let (root, format) = try PlistEngine.load(data: data)
            let doc = PlistDocument(root: root, fileURL: url, format: format)
            doc.isSecurityScoped = scoped
            documents.append(doc)
            activeDocumentID = doc.id
            showSource = false
            addRecent(url)
        } catch {
            NSLog("[XS] open FAILED: \(error)")
            if scoped { url.stopAccessingSecurityScopedResource() }
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
        if doc.isSecurityScoped, let url = doc.fileURL {
            url.stopAccessingSecurityScopedResource()
            doc.isSecurityScoped = false
        }
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

    func requestOpen() {
        showMainWindow?()
        isOpenPanelPresented = true
    }

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
        // The Save panel grants a fresh security scope on the chosen URL.
        let scoped = url.startAccessingSecurityScopedResource()
        // Release the scope held on the previous file URL, if it differs.
        if doc.isSecurityScoped, let oldURL = doc.fileURL,
           oldURL.standardizedFileURL != url.standardizedFileURL {
            oldURL.stopAccessingSecurityScopedResource()
        }
        doc.fileURL = url
        doc.isSecurityScoped = scoped
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
        let stored = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        recentBookmarks = []
        recentFiles = []
        for data in stored {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale) else { continue }
            // Drop bookmarks that no longer resolve (file moved/deleted) so the
            // display list and bookmark list stay index-aligned.
            recentBookmarks.append(data)
            recentFiles.append(url)
        }
    }

    private func addRecent(_ url: URL) {
        // The caller already holds a security scope on `url` (open/save path),
        // which is required to create a security-scoped bookmark. Fall back to a
        // plain bookmark for the unsandboxed dev build.
        let data = (try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil))
            ?? (try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil))
        guard let data else { return }

        let standard = url.standardizedFileURL
        let dupIndex = recentFiles.firstIndex { $0.standardizedFileURL == standard }
        if let dupIndex {
            recentFiles.remove(at: dupIndex)
            recentBookmarks.remove(at: dupIndex)
        }
        recentFiles.insert(url, at: 0)
        recentBookmarks.insert(data, at: 0)
        if recentBookmarks.count > maxRecents {
            recentBookmarks = Array(recentBookmarks.prefix(maxRecents))
            recentFiles = Array(recentFiles.prefix(maxRecents))
        }
        persistRecents()
    }

    /// Reopens a recent file by index, resolving its security-scoped bookmark
    /// fresh (the load-time display URL carries no usable scope).
    func openRecent(at index: Int) {
        guard recentFiles.indices.contains(index),
              recentBookmarks.indices.contains(index) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: recentBookmarks[index],
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale) else {
            // Bookmark is dead — drop it and refresh.
            recentFiles.remove(at: index)
            recentBookmarks.remove(at: index)
            persistRecents()
            return
        }
        if stale {
            // Refresh the stale bookmark in place if we still have access.
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil) {
                recentBookmarks[index] = fresh
                persistRecents()
            }
        }
        open(url: url)
    }

    private func persistRecents() {
        UserDefaults.standard.set(recentBookmarks, forKey: bookmarksKey)
    }

    func clearRecents() {
        recentFiles = []
        recentBookmarks = []
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
    }
}
