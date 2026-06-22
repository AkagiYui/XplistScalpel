//
//  PlistExportFile.swift
//  XplistScalpel
//
//  A tiny `FileDocument` used purely to drive SwiftUI's `.fileExporter` for
//  Save As. The bytes are serialised ahead of time by `AppModel`.
//

import SwiftUI
import UniformTypeIdentifiers

struct PlistExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList, .xml, .data] }
    static var writableContentTypes: [UTType] { [.propertyList, .xml, .data] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
