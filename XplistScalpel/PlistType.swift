//
//  PlistType.swift
//  XplistScalpel
//
//  The set of value types a property-list node can hold. Mirrors the
//  underlying plist data model (XML/binary) faithfully by keeping
//  Integer and Real distinct, exactly as the on-disk format does.
//

import Foundation

enum PlistType: String, CaseIterable, Identifiable, Hashable {
    case dictionary = "Dictionary"
    case array      = "Array"
    case string     = "String"
    case integer    = "Integer"
    case real       = "Real"
    case boolean    = "Boolean"
    case date       = "Date"
    case data       = "Data"

    var id: String { rawValue }

    /// Whether this type holds child nodes rather than a scalar value.
    var isContainer: Bool { self == .dictionary || self == .array }

    /// SF Symbol used to represent the type in the editor.
    var symbolName: String {
        switch self {
        case .dictionary: return "shippingbox"
        case .array:      return "square.stack.3d.up"
        case .string:     return "textformat"
        case .integer:    return "number"
        case .real:       return "function"
        case .boolean:    return "switch.2"
        case .date:       return "calendar"
        case .data:       return "doc.zipper"
        }
    }
}
