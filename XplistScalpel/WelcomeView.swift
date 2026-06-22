//
//  WelcomeView.swift
//  XplistScalpel
//
//  Shown when no document is open: quick actions and the recent-files list.
//

import SwiftUI

struct WelcomeView: View {
    let app: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text("XplistScalpel").font(.largeTitle.bold())
                Text("A precise property-list editor")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button { app.newDocument() } label: {
                    Label("New File", systemImage: "doc.badge.plus")
                }
                Button { app.requestOpen() } label: {
                    Label("Open…", systemImage: "folder")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            if !app.recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ForEach(app.recentFiles.prefix(6), id: \.self) { url in
                        Button { app.open(url: url) } label: {
                            Label(url.lastPathComponent, systemImage: "clock")
                                .lineLimit(1)
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(width: 320, alignment: .leading)
                .padding(.top, 8)
            }

            Text("Tip: drag a .plist file into the window to open it")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
