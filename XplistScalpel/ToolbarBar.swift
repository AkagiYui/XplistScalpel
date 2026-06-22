//
//  ToolbarBar.swift
//  XplistScalpel
//
//  The in-window action bar. Buttons mirror Xplist's toolbar: file ops, node
//  add/remove/move, undo/redo, expand/collapse, find, source toggle, and the
//  output format selector.
//

import SwiftUI

struct ToolbarBar: View {
    let app: AppModel

    private var doc: PlistDocument? { app.activeDocument }
    private var hasDoc: Bool { doc != nil }
    private var hasSelection: Bool { !(doc?.selection.isEmpty ?? true) }

    var body: some View {
        HStack(spacing: 4) {
            button("doc.badge.plus", "New", "New (⌘N)") { app.newDocument() }
            button("folder", "Open", "Open (⌘O)") { app.requestOpen() }
            button("square.and.arrow.down", "Save", "Save (⌘S)", enabled: hasDoc) { app.save() }

            sep()

            button("plus.rectangle.on.folder", "Add Child", "Add child node", enabled: hasDoc) { doc?.addChild() }
            button("plus", "Add Sibling", "Add sibling node", enabled: hasDoc) { doc?.addSibling() }
            button("trash", "Delete", "Delete selected", enabled: hasSelection) { doc?.deleteSelection() }
            button("plus.square.on.square", "Duplicate", "Duplicate selected", enabled: hasSelection) { doc?.duplicateSelection() }

            sep()

            button("arrow.up", "Move Up", "Move up", enabled: hasSelection) { doc?.moveUp() }
            button("arrow.down", "Move Down", "Move down", enabled: hasSelection) { doc?.moveDown() }
            button("arrow.up.arrow.down", "Sort", "Sort children", enabled: hasSelection) { doc?.sortChildren() }

            sep()

            button("arrow.uturn.backward", "Undo", "Undo (⌘Z)", enabled: doc?.canUndo ?? false) { doc?.undo() }
            button("arrow.uturn.forward", "Redo", "Redo (⇧⌘Z)", enabled: doc?.canRedo ?? false) { doc?.redo() }

            sep()

            button("chevron.down.square", "Expand", "Expand all", enabled: hasDoc) { doc?.setExpandedAll(true) }
            button("chevron.right.square", "Collapse", "Collapse all", enabled: hasDoc) { doc?.setExpandedAll(false) }

            Spacer()

            button("magnifyingglass", "Find", "Find (⌘F)", enabled: hasDoc, active: app.showFind) { app.toggleFind() }
            button(app.showSource ? "list.bullet.indent" : "doc.plaintext",
                   app.showSource ? "Tree" : "Source",
                   "Show plist as text", enabled: hasDoc, active: app.showSource) {
                app.showSource.toggle()
            }
            formatMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var formatMenu: some View {
        Menu {
            Picker("Format", selection: Binding(
                get: { doc?.format ?? .xml },
                set: { newValue in
                    guard let doc, doc.format != newValue else { return }
                    doc.format = newValue
                    doc.isDirty = true
                }
            )) {
                ForEach(PlistFileFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(doc?.format.rawValue ?? "XML", systemImage: "doc.badge.gearshape")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!hasDoc)
        .help("Output format")
    }

    private func sep() -> some View {
        Divider().frame(height: 20).padding(.horizontal, 2)
    }

    private func button(_ icon: String, _ title: String, _ help: String,
                        enabled: Bool = true, active: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 9))
            }
            .frame(minWidth: 40)
            .padding(.vertical, 2)
            .padding(.horizontal, 3)
            .background(active ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
