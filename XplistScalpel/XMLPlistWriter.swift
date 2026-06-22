//
//  XMLPlistWriter.swift
//  XplistScalpel
//
//  Serialises a `PlistNode` tree to an Apple-style XML property list, emitting
//  dictionary keys in the tree's own order. Also powers the "Show Plist Text"
//  source view.
//

import Foundation

enum XMLPlistWriter {

    static func string(from root: PlistNode) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """
        write(root, indent: 0, into: &out)
        out += "</plist>\n"
        return out
    }

    private static func write(_ node: PlistNode, indent: Int, into out: inout String) {
        let pad = String(repeating: "\t", count: indent)
        switch node.type {
        case .dictionary:
            if node.children.isEmpty {
                out += "\(pad)<dict/>\n"
            } else {
                out += "\(pad)<dict>\n"
                for child in node.children {
                    out += "\(pad)\t<key>\(escape(child.key))</key>\n"
                    write(child, indent: indent + 1, into: &out)
                }
                out += "\(pad)</dict>\n"
            }
        case .array:
            if node.children.isEmpty {
                out += "\(pad)<array/>\n"
            } else {
                out += "\(pad)<array>\n"
                for child in node.children {
                    write(child, indent: indent + 1, into: &out)
                }
                out += "\(pad)</array>\n"
            }
        case .string:
            out += "\(pad)<string>\(escape(node.stringValue))</string>\n"
        case .integer:
            out += "\(pad)<integer>\(node.intValue)</integer>\n"
        case .real:
            out += "\(pad)<real>\(PlistFormatting.realString(node.doubleValue))</real>\n"
        case .boolean:
            out += "\(pad)<\(node.boolValue ? "true" : "false")/>\n"
        case .date:
            out += "\(pad)<date>\(PlistFormatting.isoFormatter.string(from: node.dateValue))</date>\n"
        case .data:
            out += "\(pad)<data>\(node.dataValue.base64EncodedString())</data>\n"
        }
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
