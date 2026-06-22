//
//  StatusBar.swift
//  XplistScalpel
//
//  Bottom status line: edit state, file path, selection and item counts, and
//  the on-disk format.
//

import SwiftUI

struct StatusBar: View {
    let doc: PlistDocument

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: doc.isDirty ? "pencil.circle.fill" : "checkmark.circle")
                Text(doc.isDirty ? "Edited" : "Saved")
            }
            .font(.caption)
            .foregroundStyle(doc.isDirty ? .orange : .secondary)

            if let url = doc.fileURL {
                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Not saved yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !doc.selection.isEmpty {
                Text("\(doc.selection.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(doc.totalNodeCount) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(doc.format.rawValue)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
