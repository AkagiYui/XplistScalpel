//
//  PlistEngine.swift
//  XplistScalpel
//
//  Bridges raw file `Data` and the `PlistNode` tree. XML files go through the
//  order-preserving `XMLPlistParser`/`XMLPlistWriter`; binary files use the
//  system `PropertyListSerialization` (binary dict order is not observable
//  anyway). Format is auto-detected from the file's magic bytes.
//

import Foundation

enum PlistFileFormat: String, CaseIterable, Identifiable {
    case xml = "XML"
    case binary = "Binary"

    var id: String { rawValue }
}

enum PlistEngineError: LocalizedError {
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed(let message): return message
        }
    }
}

enum PlistEngine {

    /// Detects whether `data` is a binary plist (starts with "bplist") or text/XML.
    static func detectFormat(_ data: Data) -> PlistFileFormat {
        let magic = Array("bplist".utf8)
        if data.count >= magic.count && Array(data.prefix(magic.count)) == magic {
            return .binary
        }
        return .xml
    }

    /// Parses file data into a tree plus the detected on-disk format. The root
    /// node's key is normalised to "Root" (a plist root has no real key) so
    /// both the XML and binary paths produce identical trees.
    static func load(data: Data) throws -> (root: PlistNode, format: PlistFileFormat) {
        let detected = detectFormat(data)

        if detected == .xml {
            // Prefer the order-preserving parser for XML.
            if let root = try? XMLPlistParser.parse(data: data) {
                root.key = "Root"
                return (root, .xml)
            }
        }

        // Binary, or XML that the strict parser rejected: fall back to the
        // system deserialiser, which is more lenient.
        var systemFormat: PropertyListSerialization.PropertyListFormat = .xml
        let object = try PropertyListSerialization.propertyList(
            from: data, options: [], format: &systemFormat)
        let root = makeNode(fromObject: object, key: "Root")
        return (root, systemFormat == .binary ? .binary : .xml)
    }

    /// Serialises a tree to file data in the requested format.
    static func data(from root: PlistNode, format: PlistFileFormat) throws -> Data {
        switch format {
        case .xml:
            return Data(XMLPlistWriter.string(from: root).utf8)
        case .binary:
            let object = object(from: root)
            return try PropertyListSerialization.data(
                fromPropertyList: object, format: .binary, options: 0)
        }
    }

    // MARK: - Object graph <-> tree (used for binary I/O)

    static func makeNode(fromObject object: Any, key: String) -> PlistNode {
        if let dict = object as? [String: Any] {
            let node = PlistNode(key: key, type: .dictionary)
            for childKey in dict.keys.sorted() {
                let child = makeNode(fromObject: dict[childKey]!, key: childKey)
                child.parent = node
                node.children.append(child)
            }
            return node
        }
        if let array = object as? [Any] {
            let node = PlistNode(key: key, type: .array)
            for value in array {
                let child = makeNode(fromObject: value, key: "")
                child.parent = node
                node.children.append(child)
            }
            return node
        }
        if let number = object as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return PlistNode(key: key, type: .boolean, boolValue: number.boolValue)
            }
            let objCType = String(cString: number.objCType)
            if objCType == "d" || objCType == "f" {
                return PlistNode(key: key, type: .real, doubleValue: number.doubleValue)
            }
            return PlistNode(key: key, type: .integer, intValue: number.intValue)
        }
        if let date = object as? Date {
            return PlistNode(key: key, type: .date, dateValue: date)
        }
        if let data = object as? Data {
            return PlistNode(key: key, type: .data, dataValue: data)
        }
        if let string = object as? String {
            return PlistNode(key: key, type: .string, stringValue: string)
        }
        return PlistNode(key: key, type: .string, stringValue: String(describing: object))
    }

    static func object(from node: PlistNode) -> Any {
        switch node.type {
        case .dictionary:
            var dict = [String: Any]()
            for child in node.children { dict[child.key] = object(from: child) }
            return dict
        case .array:
            return node.children.map { object(from: $0) }
        case .string:
            return node.stringValue
        case .integer:
            return NSNumber(value: node.intValue)
        case .real:
            return NSNumber(value: node.doubleValue)
        case .boolean:
            return node.boolValue ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        case .date:
            return node.dateValue as NSDate
        case .data:
            return node.dataValue as NSData
        }
    }
}
