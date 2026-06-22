//
//  TreeEditorView.swift
//  XplistScalpel
//
//  The heart of the editor: a flattened, indented list of the plist tree with
//  inline editing of every node's key, type and value. Mirrors Xplist's
//  three-column (Key / Type / Value) tree view.
//

import SwiftUI

// MARK: - Column header

struct ColumnHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Key")
                .frame(width: Layout.keyColumnWidth, alignment: .leading)
            Divider()
            Text("Type")
                .frame(width: Layout.typeColumnWidth, alignment: .leading)
                .padding(.leading, 6)
            Divider()
            Text("Value")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .frame(height: 16)   // bound the height so the vertical Dividers don't make the row greedy
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

// MARK: - The list

struct TreeEditorView: View {
    @Bindable var doc: PlistDocument

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $doc.selection) {
                ForEach(doc.visibleRows) { row in
                    NodeRow(doc: doc, row: row)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .listRowSeparator(.hidden)
                        .contextMenu { RowContextMenu(doc: doc, node: row.node) }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, Layout.rowHeight)
            .onChange(of: doc.scrollTargetID) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                doc.scrollTargetID = nil
            }
        }
    }
}

// MARK: - One row

struct NodeRow: View {
    let doc: PlistDocument
    let row: RowItem
    private var node: PlistNode { row.node }

    var body: some View {
        HStack(spacing: 0) {
            // KEY column (indented)
            HStack(spacing: 4) {
                Color.clear.frame(width: CGFloat(row.depth) * Layout.indentStep, height: 1)
                disclosure
                Image(systemName: node.type.symbolName)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .frame(width: 16)
                KeyCell(doc: doc, node: node)
            }
            .frame(width: Layout.keyColumnWidth, alignment: .leading)
            .clipped()

            Divider()

            // TYPE column
            TypeCell(doc: doc, node: node)
                .frame(width: Layout.typeColumnWidth, alignment: .leading)
                .padding(.leading, 6)

            Divider()

            // VALUE column
            ValueCell(doc: doc, node: node)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .frame(height: Layout.rowHeight)
    }

    @ViewBuilder private var disclosure: some View {
        if node.type.isContainer && !node.children.isEmpty {
            Button {
                doc.toggleExpand(node)
            } label: {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: Layout.disclosureWidth)
        } else {
            Color.clear.frame(width: Layout.disclosureWidth, height: 1)
        }
    }
}

// MARK: - Key cell

struct KeyCell: View {
    let doc: PlistDocument
    let node: PlistNode
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            let parentType = node.parent?.type
            if parentType == .dictionary {
                TextField("key", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            } else if parentType == .array {
                Text("Item \(node.indexInParent ?? 0)")
                    .foregroundStyle(.secondary)
            } else {
                Text(node.key.isEmpty ? "Root" : node.key)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { text = node.key }
    }

    private func commit() {
        if text != node.key { doc.renameKey(node, to: text) }
    }
}

// MARK: - Type cell

struct TypeCell: View {
    let doc: PlistDocument
    let node: PlistNode

    var body: some View {
        Picker("", selection: Binding(
            get: { node.type },
            set: { doc.changeType(node, to: $0) }
        )) {
            ForEach(PlistType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .disabled(node.isRoot)
    }
}

// MARK: - Value cell (per type)

struct ValueCell: View {
    let doc: PlistDocument
    let node: PlistNode

    var body: some View {
        switch node.type {
        case .dictionary, .array:
            Text(node.displayValue)
                .foregroundStyle(.secondary)
        case .string:
            StringValueField(doc: doc, node: node)
        case .integer:
            NumberValueField(doc: doc, node: node, isInteger: true)
        case .real:
            NumberValueField(doc: doc, node: node, isInteger: false)
        case .boolean:
            BoolValueField(doc: doc, node: node)
        case .date:
            DateValueField(doc: doc, node: node)
        case .data:
            DataValueField(doc: doc, node: node)
        }
    }
}

struct StringValueField: View {
    let doc: PlistDocument
    let node: PlistNode
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { text = node.stringValue }
    }

    private func commit() {
        if text != node.stringValue { doc.setString(node, text) }
    }
}

struct NumberValueField: View {
    let doc: PlistDocument
    let node: PlistNode
    let isInteger: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { text = currentText }
    }

    private var currentText: String {
        isInteger ? String(node.intValue) : PlistFormatting.realString(node.doubleValue)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isInteger {
            if let value = Int(trimmed) { doc.setInt(node, value) } else { text = currentText }
        } else {
            if let value = Double(trimmed) { doc.setDouble(node, value) } else { text = currentText }
        }
    }
}

struct BoolValueField: View {
    let doc: PlistDocument
    let node: PlistNode

    var body: some View {
        Picker("", selection: Binding(
            get: { node.boolValue },
            set: { doc.setBool(node, $0) }
        )) {
            Text("YES").tag(true)
            Text("NO").tag(false)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

struct DateValueField: View {
    let doc: PlistDocument
    let node: PlistNode

    var body: some View {
        DatePicker("", selection: Binding(
            get: { node.dateValue },
            set: { doc.setDate(node, $0) }
        ), displayedComponents: [.date, .hourAndMinute])
        .labelsHidden()
        .datePickerStyle(.compact)
        .controlSize(.small)
    }
}

struct DataValueField: View {
    let doc: PlistDocument
    let node: PlistNode
    @State private var showInspector = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
            Button {
                showInspector = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showInspector, arrowEdge: .bottom) {
                DataInspector(doc: doc, node: node)
            }
        }
    }

    private var label: String {
        if node.dataValue.isEmpty { return "(empty data)" }
        let b64 = node.dataValue.base64EncodedString()
        let preview = b64.count > 28 ? String(b64.prefix(28)) + "…" : b64
        return "\(node.dataValue.count) B · \(preview)"
    }
}

// MARK: - Data inspector popover (ASCII / Hex / Base64)

struct DataInspector: View {
    let doc: PlistDocument
    let node: PlistNode
    @State private var representation: Representation = .hex
    @State private var text = ""
    @State private var parseError = false
    @Environment(\.dismiss) private var dismiss

    enum Representation: String, CaseIterable, Identifiable {
        case ascii = "ASCII", hex = "Hex", base64 = "Base64"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Data").font(.headline)
            Picker("", selection: $representation) {
                ForEach(Representation.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: representation) { _, _ in text = Self.encode(node.dataValue, as: representation) }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(width: 380, height: 170)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            if parseError {
                Text("Couldn't parse the \(representation.rawValue) value.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("\(node.dataValue.count) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .onAppear { text = Self.encode(node.dataValue, as: representation) }
    }

    private func apply() {
        if let data = Self.decode(text, as: representation) {
            doc.setData(node, data)
            dismiss()
        } else {
            parseError = true
        }
    }

    static func encode(_ data: Data, as rep: Representation) -> String {
        switch rep {
        case .ascii:  return String(decoding: data, as: UTF8.self)
        case .hex:    return data.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .base64: return data.base64EncodedString()
        }
    }

    static func decode(_ text: String, as rep: Representation) -> Data? {
        switch rep {
        case .ascii:
            return Data(text.utf8)
        case .hex:
            let hex = text.filter { $0.isHexDigit }
            guard hex.count % 2 == 0 else { return nil }
            var data = Data()
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
                data.append(byte)
                index = next
            }
            return data
        case .base64:
            return Data(base64Encoded: text.filter { !$0.isWhitespace })
        }
    }
}

// MARK: - Context menu

struct RowContextMenu: View {
    let doc: PlistDocument
    let node: PlistNode

    var body: some View {
        Button("Add Child") { doc.addChild(to: node) }
            .disabled(!node.type.isContainer)
        Button("Add Sibling") { doc.addSibling(after: node) }
            .disabled(node.isRoot)
        Divider()
        Button("Duplicate") { select(); doc.duplicateSelection() }
            .disabled(node.isRoot)
        Button("Delete") { select(); doc.deleteSelection() }
            .disabled(node.isRoot)
        Divider()
        Button("Move Up") { select(); doc.moveUp() }
            .disabled(node.isRoot)
        Button("Move Down") { select(); doc.moveDown() }
            .disabled(node.isRoot)
        if node.type.isContainer && node.children.count > 1 {
            Button("Sort Children") { select(); doc.sortChildren() }
        }
    }

    private func select() { doc.selection = [node.id] }
}
