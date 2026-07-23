# CHANGELOG

## 2.1.0

### Optimized
- Refactored `MarkdownHighlighter` by extracting unified syntax marker fade helper `applyMarkerFade`, eliminating redundant attribute application across bold, italic, code, and strikethrough logic.
- Simplified `MarkdownConverter.calculateLineIndex(for:in:)` using Swift standard library string filtering (`text[..<index].filter { $0 == "\n" }.count`).

### Cleaned
- Removed unused `MarkdownStandard` enum and `markdownStandard` configuration property from `EditorConfiguration`.
- Removed `firstLineIndent` configuration property that was not applied in paragraph styling.
- Removed dead `MarkdownConverter.isValid(_:)` stub method.

---

### 优化
- 重构 `MarkdownHighlighter`，提取统一的语法标记淡化辅助函数 `applyMarkerFade`，消除加粗、斜体、行内代码、删除线等样式的重复代码。
- 简化 `MarkdownConverter.calculateLineIndex(for:in:)`，改用 Swift 标准库切片方法 `text[..<index].filter { $0 == "\n" }.count`。

### 清理
- 移除 `EditorConfiguration` 中未使用的 `MarkdownStandard` 枚举及 `markdownStandard` 配置项。
- 移除未在段落样式中生效的 `firstLineIndent` 配置项。
- 移除无实际功能的 `MarkdownConverter.isValid(_:)` 存根方法。

## 2.0.0

### Renamed
- Package, library product, and Swift module renamed **MDEditor → MDEditorKit**. Repository moved to `github.com/SteveShi/MDEditorKit`.
- Sources folder relocated from `Sources/MDEditor/` to `Sources/MDEditorKit/`.

### Distribution
- New GitHub Actions workflow builds a macOS `MDEditorKit.xcframework`, zips it, and attaches the archive (plus SwiftPM `binaryTarget` checksum) to every tagged release.
- `build_xcframework.sh` now produces both `build/MDEditorKit.xcframework` and `build/MDEditorKit.xcframework.zip`, ready for drag-and-drop integration.

### Breaking
- Replace `import MDEditor` with `import MDEditorKit`. Public type names (`MDEditorView`, `MDEditorProxy`, `EditorConfiguration`, `EditorTheme`, `EditorStats`, …) are unchanged.
- SwiftPM consumers must update package/product name from `MDEditor` to `MDEditorKit` and bump version to `2.0.0`.

---

### 重命名
- Package、library product、Swift 模块名统一改名 **MDEditor → MDEditorKit**，仓库迁移到 `github.com/SteveShi/MDEditorKit`。
- 源码目录由 `Sources/MDEditor/` 迁至 `Sources/MDEditorKit/`。

### 分发
- 新增 GitHub Actions 工作流：每次打 tag 都会自动编译 macOS `MDEditorKit.xcframework`、打 zip，并连同 SwiftPM `binaryTarget` checksum 作为 Release 资产上传。
- `build_xcframework.sh` 现在同时产出 `build/MDEditorKit.xcframework` 与 `build/MDEditorKit.xcframework.zip`，可直接拖入 Xcode 工程使用。

### 不兼容变更
- 所有 `import MDEditor` 改为 `import MDEditorKit`；`MDEditorView`、`MDEditorProxy`、`EditorConfiguration`、`EditorTheme`、`EditorStats` 等公开类型名保持不变。
- SwiftPM 消费者需把 package/product 名由 `MDEditor` 切到 `MDEditorKit`，并锁定到 `2.0.0`。

## 1.8.0

### Added
- New `MDEditorProxy` observation hook: `onTextChange: ((String) -> Void)?` mirrors `onSelectionChange` for autosave / stats / AI streaming use cases.
- Current-line helpers on the proxy: `getCurrentLineRange()`, `getCurrentLineText()`, `replaceCurrentLine(with:)`.
- Undo / redo: `undo()`, `redo()`, `canUndo`, `canRedo`.
- Focus control: `focus()`, `resignFocus()`.
- Scrolling: `scrollRangeToVisible(_:)`, `scrollToTop()`, `scrollToBottom()`.
- Caret geometry: `caretFrameInWindow()` for popovers and inline completions.
- Selection helpers: `selectAll()`, `selectLine()`, `selectParagraph()`.
- Stats snapshot: `stats() -> EditorStats` (character / word / line counts).
- Image attachments: `insertImage(_:altText:)`; pair with new `EditorConfiguration.imageSaver` to decide storage policy.
- Attributed-string export: `exportAttributedString()` returns a snapshot of the current `NSTextStorage` for RTF / PDF pipelines.
- Indent / outdent: `indentSelection()`, `outdentSelection()`.

### Changed
- `EditorConfiguration` initializer gains an `imageSaver: (@Sendable (NSImage) -> String?)?` parameter (defaults to `nil`).

---

### 新增
- 代理新增 `onTextChange` 回调，与 `onSelectionChange` 对称，用于自动保存 / 字数刷新 / AI 监听。
- 行级辅助：`getCurrentLineRange()`、`getCurrentLineText()`、`replaceCurrentLine(with:)`。
- 撤销 / 重做：`undo()`、`redo()`、`canUndo`、`canRedo`。
- 焦点：`focus()`、`resignFocus()`。
- 滚动：`scrollRangeToVisible(_:)`、`scrollToTop()`、`scrollToBottom()`。
- 光标矩形：`caretFrameInWindow()`，用于浮层 / 内联补全定位。
- 选区辅助：`selectAll()`、`selectLine()`、`selectParagraph()`。
- 统计快照：`stats() -> EditorStats`（字符 / 词 / 行）。
- 图片插入：`insertImage(_:altText:)`，配合新的 `EditorConfiguration.imageSaver` 决定落盘策略。
- 富文本导出：`exportAttributedString()` 返回当前 `NSTextStorage` 快照，可接 RTF / PDF 导出。
- 缩进 / 反缩进：`indentSelection()`、`outdentSelection()`。

### 变更
- `EditorConfiguration` 初始化器新增 `imageSaver: (@Sendable (NSImage) -> String?)?` 参数（默认 `nil`）。

## 1.7.0

### Changes
- Added `EditorTheme` and `EditorThemeColor` to expose full editor theming (background, foreground, headings, syntax markers, emphasis, inline code, code block background, blockquote, link, insertion point).
- `EditorConfiguration` now accepts a `theme:` parameter; `MDEditorView` and `MarkdownHighlighter` consume the theme instead of a hard-coded `isDarkTheme` flag.
- `MDEditorProxy.setTheme(_:)` replaces the previous dark-mode toggle, allowing host apps to drive a complete color scheme.

### Breaking
- Removed `MarkdownHighlighter.isDarkTheme` and `MDEditorProxy.updateTheme(isDark:)`. Host apps must migrate to `EditorTheme`.

---

### 变更
- 新增 `EditorTheme` 与 `EditorThemeColor`，完整开放编辑器配色（背景、正文、标题、语法标记、强调、行内代码、代码块底色、引用、链接、光标）。
- `EditorConfiguration` 新增 `theme:` 参数；`MDEditorView` 与 `MarkdownHighlighter` 改用主题对象，不再依赖硬编码的 `isDarkTheme` 开关。
- `MDEditorProxy.setTheme(_:)` 取代旧的深色模式切换，宿主 App 可统一驱动整套配色。

### 不兼容变更
- 移除 `MarkdownHighlighter.isDarkTheme` 与 `MDEditorProxy.updateTheme(isDark:)`，宿主需迁移到 `EditorTheme`。

## 1.6.2

### Changes
- Unified Markdown parsing stack by migrating to `MarkdownParser` from the `MarkdownView` package.
- Removed redundant `apple/swift-markdown` dependency to streamline the project architecture.
- Refactored `MarkdownConverter` for better performance and consistency between editor highlighting and HTML export.

---

### 变更
- 统一了 Markdown 解析栈，迁移至 `MarkdownView` 库中的 `MarkdownParser`。
- 移除了冗余的 `apple/swift-markdown` 依赖，简化了项目架构。
- 重构了 `MarkdownConverter`，提升了性能并确保了编辑器高亮与 HTML 导出效果的一致性。
