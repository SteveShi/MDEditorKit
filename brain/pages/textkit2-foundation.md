---
id: textkit2-foundation
title: Build exclusively on Apple TextKit 2
category: decision
status: active
created: "2026-08-21T06:38:34"
updated: "2026-08-21T06:38:34"
---

<!-- compiled_truth -->
MDEditorKit is built from scratch on TextKit 2 (`NSTextLayoutManager`), bypassing legacy TextKit 1 glyph-based limitations for vastly improved paragraph styling.


## Timeline

- time: 2026-08-21T06:38:34
  kind: decision
  summary: "Created this page: Build exclusively on Apple TextKit 2"
  source: git log
  affects: [textkit2-foundation]

- time: 2026-08-21T06:38:34
  kind: decision
  summary: Adopted TextKit 2 as core text engine.
  source: git log
  affects: [textkit2-foundation]
