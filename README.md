# XplistScalpel

A native macOS property-list editor written in Swift / SwiftUI — a faithful
re-implementation of the core of [ic005k/Xplist](https://github.com/ic005k/Xplist)
(originally Qt/C++).

XplistScalpel reads and writes both **XML** and **binary** plists, presents them
in an editable **Key / Type / Value** tree, and gives you precise, surgical
control over every node.

## Features

**Files**
- Open XML *or* binary property lists (format auto-detected from magic bytes)
- Save / Save As, choosing the output format (XML or Binary) per document
- Multiple files open at once as in-window tabs
- Recent files menu, drag-and-drop to open, "Open With" via the command line
- Unsaved-changes guard when closing a tab

**Tree editing** (Key / Type / Value columns, like Xplist)
- All 8 plist types: Dictionary, Array, String, Integer, Real, Boolean, Date, Data
- Inline editing of keys (dictionaries), values (type-appropriate controls), and
  the type itself (with best-effort value conversion)
- Add child / add sibling, delete, duplicate, move up / move down
- Sort a container's children (by key for dicts, by value for arrays)
- Cut / Copy / Paste / Paste-as-child — works **across tabs**
- Expand all / collapse all
- Dedicated Data editor with ASCII / Hex / Base64 views

**Other**
- Multi-level Undo / Redo for every structural and value edit
- Find & Replace across keys and values, with case sensitivity and match navigation
- "Show Plist Text" — a live, order-preserving XML rendering of the current tree
- Status bar with item count, file path, edit state and format

### Why "order-preserving" matters

`PropertyListSerialization` returns dictionaries as unordered `NSDictionary`s,
which scrambles key order. For hand-maintained files (e.g. OpenCore's
`config.plist`) that order is meaningful, so XplistScalpel parses and writes XML
plists with its own streaming parser/writer that keeps dictionary keys in their
original, user-controlled order. Binary plists (whose order isn't observable) go
through the system serialiser.

## Architecture

The code is split into a UI-agnostic core (Foundation only) and a SwiftUI layer.

| Layer | Files |
|-------|-------|
| Core model | `PlistType`, `PlistNode`, `PlistFormatting` |
| Parsing / writing | `PlistEngine`, `XMLPlistParser`, `XMLPlistWriter` |
| Document / app state | `PlistDocument` (tree, undo, find), `AppModel` (tabs, clipboard, files) |
| Views | `ContentView`, `TreeEditorView`, `SourceView`, `FindBar`, `ToolbarBar`, `TabStrip`, `StatusBar`, `WelcomeView` |

The core layer has no SwiftUI dependency, so it is unit-tested by compiling it
standalone with `swiftc` (see *Testing* below).

## Requirements

- macOS 15.7+
- Xcode 26.1+

The app runs **App Sandbox**-enabled (required for the Mac App Store). It reads
and writes only files the user explicitly selects (open panel, drag-and-drop,
Launch Services "Open With"), plus recently-opened files recalled via
app-scoped security bookmarks.

## Building

```sh
xcodebuild -project XplistScalpel.xcodeproj -scheme XplistScalpel \
  -destination 'platform=macOS' build
```

Or just open `XplistScalpel.xcodeproj` in Xcode and run.

## Testing

The Foundation-only core and the document layer are covered by standalone test
harnesses (50 assertions): plist round-trips (XML & binary), dictionary order
preservation, `NSNumber` bool/int/real detection, type conversion, deep copy,
and the full editing/undo/find/clipboard API. Output is additionally validated
against `plutil` and shown to be semantically identical to Apple's canonical form.
