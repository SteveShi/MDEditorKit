---
id: ulysses-editor-engine-reference
title: "UlyssesMac 42.2 Editor Engine & TextKit Reference"
category: reference
status: active
tags: [ulysses, editor, textkit, rendering, architecture, reverse-engineering]
created: "2026-11-22T21:34:32"
updated: "2026-11-22T21:34:32"
---

<!-- compiled_truth -->
# UlyssesMac 42.2 Editor Engine & TextKit Reference

## Key Finding vs [[textkit2-foundation]]
Static Mach-O import and symbol analysis of `UlyssesCoreMac.framework` (v42.2, Build `84543`, 27 MB, `857` exported ObjC classes) confirms Ulysses **still runs 100% on TextKit 1** (`NSLayoutManager`, `NSTextStorage`, `NSTextContainer`, `NSTextView`, zero references to `NSTextLayoutManager`/`NSTextContentStorage`). Rather than abandoning [[textkit2-foundation]], MDEditorKit can adopt Ulysses's architectural separations while leveraging TextKit 2's native advantages.

## Four-Layer Architecture Observed in Ulysses
1. **Semantic Chunked Model (`ULChunkString` -> `ULString` -> `ULParagraph`/`ULTextElement`/`ULTextAtom`)**: Incremental per-paragraph reparsing (`ULTextParser.reparseParagraph:trackingRange:changedStructure:`) instead of whole-document regex passes.
2. **Projection Cache (`ULTextStorage`)**: Projects semantic nodes into attributed text runs and delegates fenced code blocks to `SyntaxKit` (`.tmLanguage` tokenizer).
3. **Custom Layout & Zero-Reflow Rendering (`ULLayoutManager`)**:
   - **Outdent Tags**: `ULLayoutManager(Typesetting)` pushes leading syntax markers (`#`, `>`, `-`) left of the body text column.
   - **Zero-Reflow Focus/Highlight**: `ULFocusModeRenderingModifier` and `ULHighlightRenderingModifier` override glyph colors at draw time without mutating `NSTextStorage` attributes.
4. **Decoupled Editing Semantics (`ULTextActor`, 244 methods) & Container (`ULSheetContainerView`)**:
   - Keeps auto-matching pairs/overtype, list continuation/renumbering, paragraph movement, and two-stage line-start jump out of `NSTextView`.
   - `ULSheetContainerView(TypewriterMode)` handles fixed scroll anchor (`fixedPositionFractionForMode:`), active-line highlight band, and scroll-wheel arbitration.

## High-Value Translations for MDEditorKit
1. **Lightweight Cursor Context Channel (Immediate Performance Fix)**:
   - Currently `MDEditorView.Coordinator.notifySelectionChange` reconstructs the full Markdown string (`reconstructMarkdown(from:)`) on every selection/caret change just to drive host contextual bars (e.g. `UlyssesMarkupBar`).
   - Replace with a lightweight `EditorCursorContext` emitted directly from `MarkdownTextView` / `MarkdownHighlighter` (current line block type, heading level, suggested next heading level, fenced code block state, inline vs multi-line selection) without full-document string reconstruction.
2. **Zero-Reflow Focus Mode on TextKit 2**:
   - Map `ULFocusModeRenderingModifier` to TextKit 2's native `NSTextLayoutManager.setRenderingAttributes(_:for:)` for sentence/paragraph dimming with zero layout invalidation.
3. **Outdent Syntax Markers**:
   - Use `NSParagraphStyle.headIndent` + measured marker width offset in `firstLineHeadIndent` so heading `#` markers hang cleanly left of aligned body text.
4. **Dedicated Editing Semantics Module (`MarkdownTextActor`)**:
   - Introduce an isolated editing-behavior layer for pair auto-completion + overtype, smart list continuation & ordered-list renumbering, `⌥⌘↑/↓` paragraph reordering, and two-stage `⌘←` line-start navigation.
5. **Typewriter Mode Upgrade**:
   - Extend `MarkdownTextView.scrollToCenter()` with configurable top/middle/bottom anchor fractions, subtle active-line highlight band, and temporary scroll-wheel browsing that resumes centering on typing.
6. **Future LaTeX Math (`MathKit` Pattern)**:
   - Use a single offscreen `WKWebView` with bundled KaTeX, probe exact `baseline` and `xHeight` via temporary `1px`/`1ex` `vertical-align: baseline` `<img>`, and render cached vector PDF attachments into TextKit rather than embedding live WebViews.


## Timeline

- time: 2026-11-22T21:34:32
  kind: decision
  summary: "UlyssesMac 42.2 Editor Engine & TextKit Reference"
  source: "REA static analysis of /Users/steve/Downloads/UlyssesMac.app (v42.2 build 84543)"
  affects: [ulysses-editor-engine-reference]

- time: 2026-11-22T21:34:32
  kind: decision
  summary: "Captured UlyssesMac 42.2 editor-engine architecture patterns and how to translate them onto MDEditorKit's TextKit 2 stack"
  source: "REA static analysis (inspect_macho, inspect_with_objdump, ipsw macho info)"
  affects: [ulysses-editor-engine-reference]
