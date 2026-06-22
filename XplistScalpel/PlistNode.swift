//
//  PlistNode.swift
//  XplistScalpel
//
//  The in-memory tree model. A `PlistNode` is a reference type so the editor
//  can mutate it in place and hold stable identities across re-renders. The
//  scalar payload fields are independent of each other; only the one matching
//  `type` is meaningful. Container nodes use `children`.
//

import Foundation

final class PlistNode: Identifiable {
    let id = UUID()
    weak var parent: PlistNode?

    var key: String
    var type: PlistType
    var isExpanded: Bool

    // Scalar payloads (only the field matching `type` is meaningful).
    var stringValue: String
    var intValue: Int
    var doubleValue: Double
    var boolValue: Bool
    var dateValue: Date
    var dataValue: Data

    // Children for `.dictionary` / `.array`.
    var children: [PlistNode]

    init(key: String = "",
         type: PlistType = .string,
         stringValue: String = "",
         intValue: Int = 0,
         doubleValue: Double = 0,
         boolValue: Bool = false,
         dateValue: Date = Date(timeIntervalSinceReferenceDate: 0),
         dataValue: Data = Data(),
         children: [PlistNode] = [],
         isExpanded: Bool = false) {
        self.key = key
        self.type = type
        self.stringValue = stringValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.boolValue = boolValue
        self.dateValue = dateValue
        self.dataValue = dataValue
        self.children = children
        self.isExpanded = isExpanded
        for child in children { child.parent = self }
    }

    // MARK: - Derived properties

    var isRoot: Bool { parent == nil }

    var indexInParent: Int? {
        guard let parent else { return nil }
        return parent.children.firstIndex { $0 === self }
    }

    /// Human-readable value shown in the editor's value column.
    var displayValue: String {
        switch type {
        case .dictionary, .array:
            let n = children.count
            return "(\(n) item\(n == 1 ? "" : "s"))"
        case .string:  return stringValue
        case .integer: return String(intValue)
        case .real:    return PlistFormatting.realString(doubleValue)
        case .boolean: return boolValue ? "YES" : "NO"
        case .date:    return PlistFormatting.isoFormatter.string(from: dateValue)
        case .data:    return "<\(dataValue.count) byte\(dataValue.count == 1 ? "" : "s")>"
        }
    }

    /// A lossless-ish string form of the current scalar, used when converting
    /// between scalar types so the user's value is carried over where possible.
    var scalarString: String {
        switch type {
        case .string:  return stringValue
        case .integer: return String(intValue)
        case .real:    return PlistFormatting.realString(doubleValue)
        case .boolean: return boolValue ? "true" : "false"
        case .date:    return PlistFormatting.isoFormatter.string(from: dateValue)
        case .data:    return dataValue.base64EncodedString()
        case .dictionary, .array: return ""
        }
    }

    // MARK: - Mutation

    /// Converts this node to `newType`, carrying the scalar value across where
    /// it makes sense and preserving children when staying within containers.
    func convert(to newType: PlistType) {
        guard newType != type else { return }
        let carried = scalarString
        let wasContainer = type.isContainer

        switch newType {
        case .string:
            stringValue = wasContainer ? "" : carried
        case .integer:
            let trimmed = carried.trimmingCharacters(in: .whitespaces)
            intValue = Int(trimmed) ?? Int(Double(trimmed) ?? 0)
        case .real:
            doubleValue = Double(carried.trimmingCharacters(in: .whitespaces)) ?? 0
        case .boolean:
            boolValue = ["1", "true", "yes", "y"].contains(carried.lowercased())
        case .date:
            dateValue = PlistFormatting.isoFormatter.date(from: carried) ?? dateValue
        case .data:
            dataValue = Data(base64Encoded: carried) ?? Data(carried.utf8)
        case .dictionary, .array:
            break
        }

        if newType.isContainer {
            // Keep children when converting container -> container (dict <-> array).
            if !wasContainer { children = [] }
        } else {
            children = []
        }
        type = newType
    }

    /// A full structural copy (new identities), used for the clipboard,
    /// duplication and undo snapshots. Preserves order and expansion state.
    func deepCopy() -> PlistNode {
        PlistNode(key: key,
                  type: type,
                  stringValue: stringValue,
                  intValue: intValue,
                  doubleValue: doubleValue,
                  boolValue: boolValue,
                  dateValue: dateValue,
                  dataValue: dataValue,
                  children: children.map { $0.deepCopy() },
                  isExpanded: isExpanded)
    }

    /// Total number of nodes in this subtree, including self.
    var subtreeCount: Int {
        1 + children.reduce(0) { $0 + $1.subtreeCount }
    }
}
