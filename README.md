# MDEditorKit

MDEditorKit is a native macOS Markdown editor component built on TextKit 2. It delivers a Ulysses-style "what you see is what you mean" editing surface — Markdown source stays in place, while syntax markers, headings, lists, code, images, and quotes are styled inline as you type. The package powers [MDWriter](https://github.com/SteveShi/MDWriter) and is reusable in any SwiftUI or AppKit host.

> Renamed from **MDEditor** in 2.0.0. The Swift module is now `MDEditorKit`; public type names (`MDEditorView`, `MDEditorProxy`, `EditorConfiguration`, …) are unchanged.

## Features

- **TextKit 2 engine.** Real layout and selection model, not a `WKWebView` wrapper. macOS 14+ and iOS 17+.
- **In-place Markdown styling ("MarkX").** Headings, bold, italic, strikethrough, inline code, fenced code blocks, links, images, ATX/Setext headers, blockquotes, ordered & unordered lists, GFM task lists — all rendered with native attributes while the underlying source remains a `String`.
- **Themable end-to-end.** `EditorTheme` exposes background, body, headings, syntax markers, emphasis, inline code, code-block background, blockquote, link, and caret color. Swap themes at runtime with `proxy.setTheme(_:)`.
- **Image attachments.** Local and remote images render inline; hosts plug in their own storage with `EditorConfiguration.imageProvider` / `imageSaver`.
- **Proxy-based control surface.** `MDEditorProxy` exposes a single point of contact for inserting text, wrapping selections, swapping block prefixes, finding/replacing, undo/redo, focus, scrolling, caret geometry, selection helpers, document stats, attributed-string export, and indent/outdent.
- **Real-time observation hooks.** `onTextChange` and `onSelectionChange` callbacks fire on the main actor so hosts can drive autosave, context-sensitive toolbars, stats UI, or AI streaming without re-reading the buffer.
- **Typewriter mode** centers the caret while you write.
- **Distributed both as Swift source and as a prebuilt XCFramework.**

## Requirements

- macOS 14.0+ (iOS 17.0+ supported by the source; XCFramework distribution currently ships the macOS slice only)
- Swift 6.0+
- Xcode 16+

## Installation

### Option A — Swift Package Manager (from source)

Add the dependency to `Package.swift`:

```swift
.package(url: "https://github.com/SteveShi/MDEditorKit.git", from: "2.0.0")
```

Then add `MDEditorKit` as a product dependency to your target. In an XcodeGen-driven project use:

```yaml
packages:
  MDEditorKit:
    url: https://github.com/SteveShi/MDEditorKit.git
    from: 2.0.0
targets:
  YourApp:
    dependencies:
      - package: MDEditorKit
        product: MDEditorKit
```

### Option B — Prebuilt XCFramework (Xcode binary integration)

Every tagged release ships `MDEditorKit.xcframework.zip` as a GitHub Release asset.

1. Download `MDEditorKit.xcframework.zip` from the [Releases page](https://github.com/SteveShi/MDEditorKit/releases) and unzip.
2. Drag `MDEditorKit.xcframework` into your Xcode project navigator.
3. In **Target → General → Frameworks, Libraries, and Embedded Content**, set it to **Embed & Sign**.
4. `import MDEditorKit` and you're done.

The framework is built with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, so it's safe to consume across Swift toolchain versions that share an ABI.

To rebuild locally:

```bash
./build_xcframework.sh
# → build/MDEditorKit.xcframework
# → build/MDEditorKit.xcframework.zip
# → build/MDEditorKit.xcframework.zip.checksum   (SwiftPM binaryTarget checksum)
```

## Quick Start

```swift
import SwiftUI
import MDEditorKit

struct EditorScreen: View {
    @State private var text: String = "# Hello\n\nStart writing…"
    @StateObject private var proxy = MDEditorProxy()
    @State private var configuration: EditorConfiguration = .default

    var body: some View {
        MDEditorView(text: $text, configuration: configuration, proxy: proxy)
            .onAppear {
                proxy.onTextChange = { newText in
                    // debounce + save
                }
                proxy.onSelectionChange = { range, fullText in
                    // update context-sensitive UI
                }
            }
    }
}
```

## API Reference

All editor interactions go through **`MDEditorProxy`** (`ObservableObject`). Attach it to a `MDEditorView` and call its public methods from your host. Methods are no-ops when the view isn't yet mounted.

### Observation

| Property | Type | Description |
| --- | --- | --- |
| `onSelectionChange` | `((NSRange, String) -> Void)?` | Fires on every selection or caret movement (main thread). `range.length == 0` means a pure caret. `text` is the reconstructed Markdown source. |
| `onTextChange` | `((String) -> Void)?` | Fires on every text mutation (main thread). Use for debounced autosave, stats refresh, or AI streaming hooks. |

### Basic Edits

| Method | Purpose |
| --- | --- |
| `insert(_ text: String)` | Insert text at the current selection. |
| `wrapSelection(prefix:suffix:)` | Wrap the current selection with `prefix` / `suffix` (e.g. `**` / `**`). |
| `getSelectedText() -> String?` | Return the currently selected substring. |
| `getSelectedRange() -> NSRange` | Return the current selection range. |
| `getFullText() -> String` | Return the full document as Markdown source (image attachments reconstructed back to `![]()`). |
| `replace(range:with:)` | Atomic replacement of an arbitrary range — preserves the undo stack and delegate callbacks. |
| `setSelectedRange(_ range: NSRange)` | Move the caret or selection. Clamped to the document length. |

### Current-Line Helpers

| Method | Purpose |
| --- | --- |
| `getCurrentLineRange() -> NSRange` | `NSRange` of the line containing the caret (includes the trailing newline if present). |
| `getCurrentLineText() -> String` | Text of the line containing the caret (includes the trailing newline if present). |
| `replaceCurrentLine(with replacement: String)` | Atomic replacement of the current line — typical use is Ulysses-style block-prefix swapping (`# ` → `## `, list to quote, …). |

### Undo / Redo

| Member | Purpose |
| --- | --- |
| `undo()` | Trigger the editor's undo manager. |
| `redo()` | Trigger the editor's redo manager. |
| `canUndo: Bool` | Whether undo is currently available — useful for toolbar enablement. |
| `canRedo: Bool` | Whether redo is currently available. |

### Focus

| Method | Purpose |
| --- | --- |
| `focus()` | Make the editor the window's first responder. |
| `resignFocus()` | Resign first responder if currently focused. |

### Scrolling

| Method | Purpose |
| --- | --- |
| `scrollRangeToVisible(_ range: NSRange)` | Scroll so `range` becomes visible (used by outline jumps, AI follow-cursor, etc.). |
| `scrollToTop()` | Scroll to the document head. |
| `scrollToBottom()` | Scroll to the document tail. |

### Caret Geometry

| Method | Purpose |
| --- | --- |
| `caretFrameInWindow() -> CGRect?` | Caret rect in the editor's window coordinate space — anchor floating popovers, inline completions, mention pickers, etc. Returns `nil` when the view is not mounted or no caret is positionable. |

### Selection Helpers

| Method | Purpose |
| --- | --- |
| `selectAll()` | Select the entire document. |
| `selectLine()` | Select the line under the caret (includes the trailing newline if present). |
| `selectParagraph()` | Select the paragraph under the caret (paragraphs delimited by blank lines). |

### Stats Snapshot

`stats() -> EditorStats` returns a snapshot for status-bar style UI:

```swift
public struct EditorStats: Equatable {
    public let characterCount: Int   // Swift Character (grapheme cluster) count
    public let wordCount: Int        // Whitespace-separated non-empty tokens
    public let lineCount: Int        // `\n`-delimited lines; 0 for empty text
}
```

Pair it with `onTextChange` to keep a `@Published` value live without rescanning the document yourself:

```swift
proxy.onTextChange = { [weak self] _ in
    self?.stats = self?.proxy.stats() ?? .init(characterCount: 0, wordCount: 0, lineCount: 0)
}
```

### Attachments & Export

| Method | Purpose |
| --- | --- |
| `insertImage(_ image: NSImage, altText: String = "")` | Insert an image at the caret. Persistence is delegated to `EditorConfiguration.imageSaver`; the editor writes `![alt](returned-url)` for you. No-op when no `imageSaver` is configured. |
| `exportAttributedString() -> NSAttributedString` | Snapshot of the current `NSTextStorage` (with syntax highlighting attributes) — usable for RTF / PDF export pipelines. |

### Indent / Outdent

| Method | Purpose |
| --- | --- |
| `indentSelection()` | Add one Tab in front of every selected line (or the caret line when nothing is selected). |
| `outdentSelection()` | Remove one leading Tab, or 2 / 4 leading spaces, from every selected line. |

### Find & Replace

| Method | Purpose |
| --- | --- |
| `findNext(text:)` | Find the next case-insensitive occurrence; wraps around. |
| `findPrevious(text:)` | Find the previous case-insensitive occurrence; wraps around. |
| `replace(search:with:)` | Replace the current selection if it matches `search` (case-insensitive). |
| `replaceAll(search:with:)` | Replace every occurrence (case-insensitive). |

### Miscellaneous

| Method | Purpose |
| --- | --- |
| `print()` | Trigger the platform print panel. |
| `setTheme(_ theme: EditorTheme)` | Swap the editor theme at runtime. |

## EditorConfiguration Highlights

`EditorConfiguration` controls visual layout and host-supplied hooks. Two callbacks are most relevant to integrations:

| Field | Signature | Purpose |
| --- | --- | --- |
| `imageProvider` | `(@Sendable (String) -> NSImage?)?` | Resolve a Markdown image reference (filename) back into an in-line `NSImage` for preview. |
| `imageSaver` | `(@Sendable (NSImage) -> String?)?` | Persist an `NSImage` (from paste, drag, or `proxy.insertImage`) and return the URL or relative path used inside the Markdown reference. Return `nil` to opt out — the editor inserts nothing in that case. |

## Releases

Tagged releases are published on GitHub. Each release includes:

- Source archive (`.tar.gz` / `.zip`) — used by SwiftPM.
- `MDEditorKit.xcframework.zip` — prebuilt macOS XCFramework for Xcode binary integration.
- `MDEditorKit.xcframework.zip.checksum` — SwiftPM `binaryTarget` checksum if you want to host a binary package.

## License

This project is licensed under the [Mozilla Public License 2.0 (MPL-2.0)](LICENSE).
