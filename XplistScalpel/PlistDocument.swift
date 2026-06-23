//
//  PlistDocument.swift
//  XplistScalpel
//
//  One open property-list file (a tab). Owns the tree, the flattened list of
//  visible rows for the editor, selection, find state, and a snapshot-based
//  undo/redo stack. All structural edits funnel through here so undo and the
//  dirty flag stay correct.
//

import Foundation
import Observation

/// A flattened, depth-tagged row for the tree editor's `List`.
struct RowItem: Identifiable {
    let node: PlistNode
    let depth: Int
    var id: UUID { node.id }
}

@Observable
final class PlistDocument: Identifiable {
    let id = UUID()

    var root: PlistNode
    var fileURL: URL?
    var format: PlistFileFormat
    var isDirty: Bool = false

    /// True while this document holds an active security-scoped-resource grant
    /// on `fileURL` (App Sandbox). The grant is started when the file is opened
    /// and released when the tab is closed.
    @ObservationIgnored var isSecurityScoped: Bool = false

    var selection: Set<UUID> = []
    var visibleRows: [RowItem] = []
    /// Set to request the editor scroll a given row into view.
    var scrollTargetID: UUID?

    // Find / replace state.
    var searchQuery: String = ""
    var caseSensitive: Bool = false
    var matches: [UUID] = []
    var currentMatchIndex: Int = -1

    @ObservationIgnored private var undoStack: [PlistNode] = []
    @ObservationIgnored private var redoStack: [PlistNode] = []
    @ObservationIgnored private var nodeIndex: [UUID: PlistNode] = [:]

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var displayName: String { fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }
    var fileName: String { fileURL?.lastPathComponent ?? "Untitled" }
    var totalNodeCount: Int { max(0, root.subtreeCount - 1) }

    init(root: PlistNode, fileURL: URL?, format: PlistFileFormat) {
        self.root = root
        self.fileURL = fileURL
        self.format = format
        root.isExpanded = true
        rebuildRows()
    }

    static func newDocument() -> PlistDocument {
        let root = PlistNode(key: "Root", type: .dictionary)
        return PlistDocument(root: root, fileURL: nil, format: .xml)
    }

    // MARK: - Row flattening / lookup

    func rebuildRows() {
        var rows: [RowItem] = []
        var index: [UUID: PlistNode] = [:]
        func walk(_ node: PlistNode, depth: Int, visible: Bool) {
            index[node.id] = node
            if visible { rows.append(RowItem(node: node, depth: depth)) }
            let childrenVisible = visible && node.type.isContainer && node.isExpanded
            if node.type.isContainer {
                for child in node.children {
                    walk(child, depth: depth + 1, visible: childrenVisible)
                }
            }
        }
        walk(root, depth: 0, visible: true)
        visibleRows = rows
        nodeIndex = index
    }

    func node(for id: UUID) -> PlistNode? { nodeIndex[id] }

    /// Selected nodes in tree (document) order.
    var selectedNodesInOrder: [PlistNode] {
        var result: [PlistNode] = []
        func walk(_ node: PlistNode) {
            if selection.contains(node.id) { result.append(node) }
            node.children.forEach(walk)
        }
        walk(root)
        return result
    }

    var primaryNode: PlistNode? { selectedNodesInOrder.first }

    // MARK: - Undo / redo

    private func pushUndo() {
        undoStack.append(root.deepCopy())
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(root.deepCopy())
        root = snapshot
        selection = []
        isDirty = true
        rebuildRows()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(root.deepCopy())
        root = snapshot
        selection = []
        isDirty = true
        rebuildRows()
    }

    private func markDirty() { isDirty = true }

    // MARK: - Expansion

    func toggleExpand(_ node: PlistNode) {
        node.isExpanded.toggle()
        rebuildRows()
    }

    func setExpandedAll(_ expanded: Bool) {
        func walk(_ node: PlistNode) {
            if node.type.isContainer { node.isExpanded = expanded }
            node.children.forEach(walk)
        }
        walk(root)
        rebuildRows()
    }

    private func expandAncestors(of node: PlistNode) {
        var parent = node.parent
        while let current = parent {
            current.isExpanded = true
            parent = current.parent
        }
    }

    // MARK: - Scalar value edits

    func setString(_ node: PlistNode, _ value: String) {
        guard node.stringValue != value else { return }
        pushUndo(); node.stringValue = value; markDirty()
    }
    func setInt(_ node: PlistNode, _ value: Int) {
        guard node.intValue != value else { return }
        pushUndo(); node.intValue = value; markDirty()
    }
    func setDouble(_ node: PlistNode, _ value: Double) {
        guard node.doubleValue != value else { return }
        pushUndo(); node.doubleValue = value; markDirty()
    }
    func setBool(_ node: PlistNode, _ value: Bool) {
        guard node.boolValue != value else { return }
        pushUndo(); node.boolValue = value; markDirty()
    }
    func setDate(_ node: PlistNode, _ value: Date) {
        guard node.dateValue != value else { return }
        pushUndo(); node.dateValue = value; markDirty()
    }
    func setData(_ node: PlistNode, _ value: Data) {
        guard node.dataValue != value else { return }
        pushUndo(); node.dataValue = value; markDirty()
    }

    func renameKey(_ node: PlistNode, to newKey: String) {
        guard node.parent?.type == .dictionary, node.key != newKey else { return }
        pushUndo(); node.key = newKey; markDirty()
    }

    func changeType(_ node: PlistNode, to type: PlistType) {
        guard node.type != type else { return }
        pushUndo()
        node.convert(to: type)
        if type.isContainer { node.isExpanded = true }
        markDirty()
        rebuildRows()
    }

    // MARK: - Structural edits

    private func uniqueKey(in parent: PlistNode, base: String) -> String {
        let baseKey = base.isEmpty ? "New item" : base
        let existing = Set(parent.children.map { $0.key })
        if !existing.contains(baseKey) { return baseKey }
        var n = 2
        while existing.contains("\(baseKey) \(n)") { n += 1 }
        return "\(baseKey) \(n)"
    }

    private func makeNewChild(for parent: PlistNode) -> PlistNode {
        let child = PlistNode(type: .string, stringValue: "")
        if parent.type == .dictionary { child.key = uniqueKey(in: parent, base: "New item") }
        child.parent = parent
        return child
    }

    /// Adds a child to a container (or to the selected container).
    func addChild(to target: PlistNode? = nil) {
        let base = target ?? primaryNode ?? root
        let parent = base.type.isContainer ? base : (base.parent ?? root)
        guard parent.type.isContainer else { return }
        pushUndo()
        let child = makeNewChild(for: parent)
        parent.children.append(child)
        parent.isExpanded = true
        markDirty(); rebuildRows()
        selection = [child.id]; scrollTargetID = child.id
    }

    /// Adds a sibling immediately after the selected node.
    func addSibling(after target: PlistNode? = nil) {
        guard let node = target ?? primaryNode else { addChild(to: root); return }
        guard let parent = node.parent,
              let index = parent.children.firstIndex(where: { $0 === node }) else {
            addChild(to: node); return
        }
        pushUndo()
        let sibling = makeNewChild(for: parent)
        parent.children.insert(sibling, at: index + 1)
        markDirty(); rebuildRows()
        selection = [sibling.id]; scrollTargetID = sibling.id
    }

    func deleteSelection() {
        let nodes = selectedNodesInOrder.filter { $0.parent != nil }
        guard !nodes.isEmpty else { return }
        pushUndo()
        for node in nodes {
            node.parent?.children.removeAll { $0 === node }
            node.parent = nil
        }
        selection = []
        markDirty(); rebuildRows()
    }

    func duplicateSelection() {
        let nodes = selectedNodesInOrder.filter { $0.parent != nil }
        guard !nodes.isEmpty else { return }
        pushUndo()
        var newIDs: Set<UUID> = []
        for node in nodes {
            guard let parent = node.parent,
                  let index = parent.children.firstIndex(where: { $0 === node }) else { continue }
            let copy = node.deepCopy()
            if parent.type == .dictionary { copy.key = uniqueKey(in: parent, base: node.key) }
            copy.parent = parent
            parent.children.insert(copy, at: index + 1)
            newIDs.insert(copy.id)
        }
        selection = newIDs
        markDirty(); rebuildRows()
    }

    func moveUp() {
        guard let node = primaryNode, let parent = node.parent,
              let index = parent.children.firstIndex(where: { $0 === node }), index > 0 else { return }
        pushUndo()
        parent.children.swapAt(index, index - 1)
        markDirty(); rebuildRows()
    }

    func moveDown() {
        guard let node = primaryNode, let parent = node.parent,
              let index = parent.children.firstIndex(where: { $0 === node }),
              index < parent.children.count - 1 else { return }
        pushUndo()
        parent.children.swapAt(index, index + 1)
        markDirty(); rebuildRows()
    }

    /// Sorts the selected container's children (by key for dictionaries, by
    /// displayed value for arrays).
    func sortChildren() {
        let base = primaryNode ?? root
        let container = base.type.isContainer ? base : (base.parent ?? root)
        guard container.type.isContainer, !container.children.isEmpty else { return }
        pushUndo()
        if container.type == .dictionary {
            container.children.sort { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        } else {
            container.children.sort { $0.displayValue.localizedStandardCompare($1.displayValue) == .orderedAscending }
        }
        markDirty(); rebuildRows()
    }

    // MARK: - Clipboard insertion

    enum InsertMode { case siblingAfter, child }

    /// Inserts copies of `nodes` relative to the current selection.
    func insert(_ nodes: [PlistNode], mode: InsertMode) {
        guard !nodes.isEmpty else { return }
        let target = primaryNode ?? root
        pushUndo()
        var newIDs: Set<UUID> = []

        func place(_ node: PlistNode, into parent: PlistNode, at index: Int?) {
            if parent.type == .dictionary {
                node.key = uniqueKey(in: parent, base: node.key)
            } else {
                node.key = ""
            }
            node.parent = parent
            if let index { parent.children.insert(node, at: index) }
            else { parent.children.append(node) }
            newIDs.insert(node.id)
        }

        switch mode {
        case .child:
            let parent = target.type.isContainer ? target : (target.parent ?? root)
            guard parent.type.isContainer else { return }
            for node in nodes { place(node, into: parent, at: nil) }
            parent.isExpanded = true
        case .siblingAfter:
            if let parent = target.parent,
               let index = parent.children.firstIndex(where: { $0 === target }) {
                var insertAt = index + 1
                for node in nodes { place(node, into: parent, at: insertAt); insertAt += 1 }
            } else {
                for node in nodes { place(node, into: root, at: nil) }
                root.isExpanded = true
            }
        }
        selection = newIDs
        markDirty(); rebuildRows()
    }

    // MARK: - Find / replace

    func runSearch() {
        matches = []
        currentMatchIndex = -1
        let query = searchQuery
        guard !query.isEmpty else { return }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        func matchesText(_ haystack: String) -> Bool {
            haystack.range(of: query, options: options) != nil
        }
        func walk(_ node: PlistNode) {
            if matchesText(node.key) || matchesText(node.displayValue) {
                matches.append(node.id)
            }
            node.children.forEach(walk)
        }
        walk(root)
        if !matches.isEmpty { goToMatch(0) }
    }

    func goToMatch(_ index: Int) {
        guard !matches.isEmpty else { return }
        let wrapped = ((index % matches.count) + matches.count) % matches.count
        currentMatchIndex = wrapped
        let id = matches[wrapped]
        if let node = nodeIndex[id] { expandAncestors(of: node) }
        rebuildRows()
        selection = [id]
        scrollTargetID = id
    }

    func nextMatch() { goToMatch(currentMatchIndex + 1) }
    func previousMatch() { goToMatch(currentMatchIndex - 1) }

    func replaceCurrent(with replacement: String) {
        guard currentMatchIndex >= 0, currentMatchIndex < matches.count,
              let node = nodeIndex[matches[currentMatchIndex]] else { return }
        pushUndo()
        applyReplace(on: node, replacement: replacement)
        markDirty(); rebuildRows(); runSearch()
    }

    func replaceAll(with replacement: String) {
        guard !matches.isEmpty else { return }
        pushUndo()
        for id in matches {
            if let node = nodeIndex[id] { applyReplace(on: node, replacement: replacement) }
        }
        markDirty(); rebuildRows(); runSearch()
    }

    private func applyReplace(on node: PlistNode, replacement: String) {
        let query = searchQuery
        guard !query.isEmpty else { return }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        if node.parent?.type == .dictionary, node.key.range(of: query, options: options) != nil {
            node.key = node.key.replacingOccurrences(of: query, with: replacement, options: options)
        }
        if node.type == .string, node.stringValue.range(of: query, options: options) != nil {
            node.stringValue = node.stringValue.replacingOccurrences(
                of: query, with: replacement, options: options)
        }
    }
}
