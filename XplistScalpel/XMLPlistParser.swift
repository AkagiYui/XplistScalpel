//
//  XMLPlistParser.swift
//  XplistScalpel
//
//  A streaming (SAX) parser for XML property lists that builds a `PlistNode`
//  tree while **preserving dictionary key order**. This is the key advantage
//  over `PropertyListSerialization`, whose `NSDictionary` output loses the
//  original ordering — order matters for hand-edited files like OpenCore's
//  config.plist.
//

import Foundation

final class XMLPlistParser: NSObject, XMLParserDelegate {

    static func parse(data: Data) throws -> PlistNode {
        let handler = XMLPlistParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        guard parser.parse() else {
            throw PlistEngineError.parseFailed(
                parser.parserError?.localizedDescription ?? "Invalid XML property list")
        }
        guard let root = handler.root else {
            throw PlistEngineError.parseFailed("Property list is empty")
        }
        return root
    }

    private var root: PlistNode?
    private var stack: [PlistNode] = []      // open container nodes
    private var pendingKey: String?          // last <key> seen inside a <dict>
    private var buffer = ""
    private var isCapturing = false
    private var currentLeaf: PlistNode?

    /// Attaches a freshly created node to the current container (or makes it
    /// the root), assigning its key from the pending `<key>` when appropriate.
    private func attach(_ node: PlistNode) {
        if let parent = stack.last {
            if parent.type == .dictionary {
                node.key = pendingKey ?? ""
                pendingKey = nil
            } else {
                node.key = ""
            }
            node.parent = parent
            parent.children.append(node)
        } else if root == nil {
            root = node
        }
    }

    private static let leafTypes: [String: PlistType] = [
        "string": .string, "integer": .integer, "real": .real,
        "date": .date, "data": .data,
    ]

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "plist":
            break
        case "dict":
            let node = PlistNode(type: .dictionary)
            attach(node)
            stack.append(node)
        case "array":
            let node = PlistNode(type: .array)
            attach(node)
            stack.append(node)
        case "key":
            buffer = ""
            isCapturing = true
        case "true", "false":
            attach(PlistNode(type: .boolean, boolValue: elementName == "true"))
        default:
            if let leafType = Self.leafTypes[elementName] {
                buffer = ""
                isCapturing = true
                let node = PlistNode(type: leafType)
                attach(node)
                currentLeaf = node
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCapturing { buffer += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if isCapturing, let string = String(data: CDATABlock, encoding: .utf8) {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "plist", "true", "false":
            break
        case "dict", "array":
            if !stack.isEmpty { stack.removeLast() }
        case "key":
            pendingKey = buffer
            isCapturing = false
            buffer = ""
        case "string":
            currentLeaf?.stringValue = buffer
            finishLeaf()
        case "integer":
            currentLeaf?.intValue = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            finishLeaf()
        case "real":
            currentLeaf?.doubleValue = Double(buffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            finishLeaf()
        case "date":
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            currentLeaf?.dateValue = PlistFormatting.isoFormatter.date(from: text)
                ?? Date(timeIntervalSinceReferenceDate: 0)
            finishLeaf()
        case "data":
            let cleaned = buffer.filter { !$0.isWhitespace }
            currentLeaf?.dataValue = Data(base64Encoded: cleaned) ?? Data()
            finishLeaf()
        default:
            break
        }
    }

    private func finishLeaf() {
        isCapturing = false
        buffer = ""
        currentLeaf = nil
    }
}
