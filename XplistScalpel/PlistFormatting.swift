//
//  PlistFormatting.swift
//  XplistScalpel
//
//  Shared, reusable formatters for the canonical textual representation of
//  plist scalar values (dates, reals). Centralised so parsing and writing
//  always agree.
//

import Foundation

enum PlistFormatting {

    /// ISO-8601 formatter matching Apple's plist `<date>` representation,
    /// e.g. `2024-01-31T08:00:00Z`.
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Renders a `Double` for `<real>` output. Keeps a trailing `.0` for whole
    /// numbers so the value is unambiguously a real rather than an integer.
    static func realString(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 && value.isFinite {
            return String(format: "%.1f", value)
        }
        return String(value)
    }
}
