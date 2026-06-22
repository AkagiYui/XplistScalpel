//
//  FindBar.swift
//  XplistScalpel
//
//  Find & replace bar. Searches keys and values, navigates matches, and can
//  replace within keys and string values (with optional case sensitivity).
//

import SwiftUI

struct FindBar: View {
    @Bindable var doc: PlistDocument
    let app: AppModel
    @State private var replacement = ""
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find key or value", text: $doc.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($findFocused)
                    .onSubmit { doc.nextMatch() }
                    .onChange(of: doc.searchQuery) { _, _ in doc.runSearch() }

                Text(matchLabel)
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48)

                Button { doc.previousMatch() } label: { Image(systemName: "chevron.up") }
                    .disabled(doc.matches.isEmpty)
                Button { doc.nextMatch() } label: { Image(systemName: "chevron.down") }
                    .disabled(doc.matches.isEmpty)

                Toggle(isOn: $doc.caseSensitive) {
                    Text("Aa")
                }
                .toggleStyle(.button)
                .help("Case sensitive")
                .onChange(of: doc.caseSensitive) { _, _ in doc.runSearch() }

                Button { app.toggleFind() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .help("Close find")
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath").foregroundStyle(.secondary)
                TextField("Replace with", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                Button("Replace") { doc.replaceCurrent(with: replacement) }
                    .disabled(doc.matches.isEmpty)
                Button("Replace All") { doc.replaceAll(with: replacement) }
                    .disabled(doc.matches.isEmpty)
            }
        }
        .padding(8)
        .background(.bar)
        .onAppear { findFocused = true }
    }

    private var matchLabel: String {
        if doc.searchQuery.isEmpty { return "" }
        if doc.matches.isEmpty { return "No results" }
        return "\(doc.currentMatchIndex + 1) of \(doc.matches.count)"
    }
}
