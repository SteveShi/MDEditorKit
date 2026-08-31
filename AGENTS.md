# MDEditor - Agent Guidelines & Instructions

This file provides operational guidance to AI coding agents (Antigravity, Cursor, Codex, OpenCode, Pi, etc.) working in this repository.

## Project Overview

MDEditorKit is a native macOS Markdown editor component built on TextKit 2, delivering Ulysses-style "what you see is what you mean" editing. The package provides a SwiftUI-compatible editor where Markdown source stays in place while syntax markers, headings, lists, code, images, and quotes are styled inline as you type.

**Key characteristics:**
- TextKit 2 engine (not a WebView wrapper)
- In-place Markdown styling ("MarkX") with native attributes
- Distributed as both Swift source and prebuilt XCFramework
- Supports macOS 14+ and iOS 17+
- Swift 6.0+ with strict concurrency enabled

## Build Commands

### Swift Package Manager (Development)

```bash
# Build the package
swift build

# Build for release
swift build -c release

# Clean build artifacts
swift package clean
rm -rf .build
```

### XCFramework Distribution Build

```bash
# Build prebuilt XCFramework for binary distribution
./build_xcframework.sh

# Output: build/MDEditorKit.xcframework
# Output: build/MDEditorKit.xcframework.zip
# Output: build/MDEditorKit.xcframework.zip.checksum
```

The build script:
1. Generates Xcode project using `xcodegen` (requires: `brew install xcodegen xcbeautify`)
2. Archives for macOS (universal binary: Apple Silicon + Intel)
3. Creates XCFramework with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`
4. Zips for distribution and computes SwiftPM checksum

**Important build flags:**
- `MACOSX_DEPLOYMENT_TARGET=14.0`
- `OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface -enable-experimental-feature Lifetimes"`
- Swift 6 language mode is enabled

### Xcode Project Generation

The project uses XcodeGen for project file generation:

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Opens MDEditorKit.xcodeproj
open MDEditorKit.xcodeproj
```

## Architecture

### Core Components

**MDEditorView** (`MDEditorView.swift`, ~692 lines)
- SwiftUI `NSViewRepresentable` wrapper around the TextKit 2 editor
- Manages bidirectional sync between SwiftUI `@Binding var text` and the underlying `NSTextStorage`
- **Critical pattern**: Uses `reconstructMarkdown(from:)` to restore Markdown source from rich text, handling image attachments that are replaced with `NSTextAttachment` objects
- The `Coordinator` implements `NSTextViewDelegate` and bridges all editor events to SwiftUI
- Handles the "MarkdownSource" custom attribute that preserves original Markdown for attachments

**MarkdownHighlighter** (`MarkdownHighlighter.swift`, ~599 lines)
- Applies Ulysses-style inline syntax highlighting using regex patterns
- **Two-phase rendering**:
  1. Non-destructive styling (colors, fonts, attributes)
  2. Destructive replacements (images converted to `NSTextAttachment`)
- Preserves original Markdown in a custom `"MarkdownSource"` attribute on attachments
- Uses `NSTextStorage.beginEditing()` / `endEditing()` for atomic updates
- Image replacements are applied back-to-front to maintain range validity

**MDEditorProxy** (`MDEditorProxy.swift`, ~239 lines)
- `ObservableObject` that exposes the entire editor API surface
- All interactions with the editor go through this proxy
- Provides observation hooks: `onTextChange` and `onSelectionChange`
- Methods are no-ops when the view isn't mounted (actions are `nil`)
- Hosts wire up actions in `setupProxyActions()` during view lifecycle

**MarkdownTextView** (referenced but defined in `MDEditorView.swift`)
- Custom `NSTextView` subclass that handles:
  - Typewriter mode (centers caret while typing)
  - Custom typing attributes
  - Markdown-aware text insertion
  - Integration with `MarkdownHighlighter`

**EditorConfiguration** (`EditorConfiguration.swift`, ~130 lines)
- Configuration struct controlling visual layout and host-supplied hooks
- Key callbacks:
  - `imageProvider: (@Sendable (String) -> NSImage?)?` - resolves image references to `NSImage`
  - `imageSaver: (@Sendable (NSImage) -> String?)?` - persists images and returns URL/path

**EditorTheme** (`EditorTheme.swift`, ~125 lines)
- Themable color system for all editor elements
- Supports runtime theme swapping via `proxy.setTheme(_:)`

### Data Flow

1. **User types** → `NSTextView` updates `NSTextStorage`
2. **MarkdownHighlighter** applies styling to changed range
3. **Coordinator.textDidChange** reconstructs Markdown source (handling attachments)
4. **SwiftUI binding** updates with reconstructed source
5. **proxy.onTextChange** callback fires for host observation

**Critical invariant**: The `"MarkdownSource"` attribute preserves original Markdown syntax for elements that are visually replaced (like images), ensuring round-trip fidelity when reconstructing the source.

### Dependencies

- **MarkdownView** (https://github.com/SteveShi/MarkdownView.git, from: 1.0.0)
  - Provides `MarkdownView` and `MarkdownParser` products
  - Used for Markdown parsing and preview rendering

## Swift 6 Concurrency

The codebase uses Swift 6 with strict concurrency checking:
- `MarkdownHighlighter` is marked `@unchecked Sendable` (contains mutable state but is main-actor bound)
- Image provider/saver callbacks are `@Sendable` closures
- All `NSTextView` interactions happen on the main actor

## CI/CD

GitHub Actions workflow (`.github/workflows/release.yml`):
- Triggers on version tags (`[0-9]+.[0-9]+.[0-9]+` or `v[0-9]+.[0-9]+.[0-9]+`)
- Runs on `macos-26` with latest stable Xcode
- Builds XCFramework and creates GitHub Release with:
  - `MDEditorKit.xcframework.zip`
  - `MDEditorKit.xcframework.zip.checksum` (for SwiftPM `binaryTarget`)
  - SHA-256 hash in release notes

## Development Notes

### When modifying the editor core:

1. **Markdown reconstruction** is critical - any change to how attachments or attributes are stored must update `reconstructMarkdown(from:)` in `MDEditorView.swift:57`

2. **Highlighting must preserve attachments** - when resetting attributes in `MarkdownHighlighter`, the double-backup mechanism (lines 126-145) prevents losing image attachments

3. **Range invalidation** - image replacements change `NSTextStorage` length, so they must be applied back-to-front (highest location first)

4. **Proxy actions are optional** - all proxy methods check if their action closure is non-nil, making them safe to call before view mount

### When adding new Markdown syntax:

1. Add regex pattern to `MarkdownHighlighter.patterns` (line ~48)
2. Add corresponding `HighlightStyle` enum case
3. Implement styling in the switch statement in `applyStyle()`
4. If the syntax requires destructive replacement (like images), add to the two-phase rendering logic

### XcodeGen project structure:

The `project.yml` defines a single framework target with:
- Platform: macOS 14.0+
- `BUILD_LIBRARY_FOR_DISTRIBUTION: YES` for ABI stability
- Dependencies on MarkdownView package products

Regenerate the Xcode project after modifying `project.yml`:
```bash
xcodegen generate
```

## Testing

Currently, this repository does not contain a Tests directory. The package is tested through integration in the consuming app (MDWriter).

## Release Process

1. Update version in relevant files
2. Update `CHANGELOG.md`
3. Commit changes
4. Create and push version tag: `git tag 2.x.x && git push origin 2.x.x`
5. GitHub Actions automatically builds and publishes the release with XCFramework

## Package Naming

**Historical note**: The package was renamed from "MDEditor" to "MDEditorKit" in version 2.0.0. The Swift module is `MDEditorKit`, but public type names (`MDEditorView`, `MDEditorProxy`, etc.) remain unchanged for API compatibility.

<!-- BEGIN brain.md -->
## Project Brain

This project keeps a **Project Brain**: a persistent memory layer of its durable decisions, requirements, and constraints. Read `./BRAIN.md` for the full read/write contract.

Maintain the brain as part of normal coding work — not as a separate task. While discussing or implementing features:
- **Start of a task:** load relevant context with the `brain` CLI (`list-pages`, `read-page`, `read-root`). Prefer a narrow read over scanning everything.
- **When a decision, requirement, constraint, or durable insight settles** (in chat or while coding): capture it immediately via the `brain` CLI. Do not wait to be asked and do not batch it for later.
- **Pure implementation with no new decision:** do not write to the brain.
- **When overturning a prior conclusion:** update the page (`update-truth` and/or `append-timeline` with `kind: reversal`, or `archive-page`).
- Only store what will still matter in six months and is hard to reconstruct from the code alone.
- All reads and writes go through the `brain` CLI — never hand-edit brain files.

The brain skills (`brain-setup`, `brain-page`, `brain-ingest`, `brain-bootstrap`) are installed in your global skills directory. Prefer `brain init` to scaffold a new project.
<!-- END brain.md -->
