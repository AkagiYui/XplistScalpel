//
//  TabStrip.swift
//  XplistScalpel
//
//  A horizontal strip of open-document tabs, like Xplist's tab bar.
//

import SwiftUI

struct TabStrip: View {
    let app: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(app.documents) { doc in
                    TabButton(app: app, doc: doc, isActive: doc.id == app.activeDocumentID)
                }
            }
        }
        .background(.bar)
    }
}

private struct TabButton: View {
    let app: AppModel
    let doc: PlistDocument
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(doc.isDirty ? Color.orange : .clear)
                .frame(width: 6, height: 6)
            Text(doc.fileName)
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(isActive ? .primary : .secondary)
            Button {
                app.requestClose(doc)
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 220)
        .background(isActive ? Color.accentColor.opacity(0.18) : .clear)
        .overlay(alignment: .trailing) { Divider() }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? Color.accentColor : .clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            app.activeDocumentID = doc.id
            app.showSource = false
        }
        .help(doc.fileURL?.path ?? "Untitled")
    }
}
