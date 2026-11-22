# CHANGELOG

## 2.3.1

### Fixed
- Moved `SWIFT_VERIFY_EMITTED_MODULE_INTERFACE` and `OTHER_SWIFT_FLAGS` (`$(inherited)`) into the `MDEditorKit` target settings in `Project.swift` instead of passing `OTHER_SWIFT_FLAGS` globally on the `xcodebuild archive` command line in `build_xcframework.sh`, preventing XCFramework builds from overriding `swift-collections`'s `-enable-builtin-module` flag (`no such module 'Builtin'`).

---

### 修复
- 将 `SWIFT_VERIFY_EMITTED_MODULE_INTERFACE` 与带 `$(inherited)` 的 `OTHER_SWIFT_FLAGS` 收拢至 `Project.swift` 的 `MDEditorKit` target 配置中，不再在 `build_xcframework.sh` 的 `xcodebuild archive` 命令行全局覆写 `OTHER_SWIFT_FLAGS`，修复构建 XCFramework 时覆盖上游 `swift-collections` 的 `-enable-builtin-module` 导致的 `no such module 'Builtin'` 报错。

## 2.3.0

### Added
- Native offline LaTeX math rendering (`MathRenderer`) powered by `SwiftMath` with LRU caching and baseline-aligned vector attachments for inline (`$...$`) and display (`$$...$$`) equations, plus caret-aware live source editing and graceful fallback on syntax errors.
- Dedicated editing semantics engine (`MarkdownTextActor`): smart auto-pairing with overtype skip and empty-pair backspace deletion, backspace unwrapping of math attachments back to raw LaTeX, automatic list/quote continuation with ordered-list renumbering, two-stage smart Home (`⌘←`), and paragraph reordering (`⌥⌘↑` / `⌥⌘↓`).
- Lightweight cursor context channel (`EditorCursorContext`, `EditorBlockContext`, `EditorEntityInfo`, `EditorWikiLinkQuery`) and `MDEditorProxy.onCursorContextChange` / `onEntityActivate` hooks, eliminating full-document Markdown reconstruction on arrow-key navigation.
- Ulysses-style writing comfort options in `EditorConfiguration`: syntax marker outdenting (`outdentSyntaxMarkers`), zero-reflow sentence/paragraph focus mode (`focusMode`), configurable typewriter vertical anchor (`typewriterAnchor`: top/center/bottom) with scroll-wheel browse pause, subtle active-line highlight (`highlightCurrentLine`), and inline math toggle (`renderMathInline`).
- `[[WikiLink]]` syntax highlighting and `MDEditorProxy` helpers for paragraph movement, inline/display math insertion, and entity activation.

### Fixed
- Preserved `$$...$$` and `\(...\)` delimiters for `.math` nodes in `MarkdownConverter.toHTML(_:imageResolver:)` so HTML/PDF KaTeX renderers typeset exported equations accurately.
- Applied `EditorConfiguration.paragraphSpacing` in `MarkdownHighlighter.createBaseParagraphStyle()` and allowed live configuration/theme updates in `MDEditorView.updateNSView` while focused without overwriting active text input.

---

### 新增
- 原生离线 LaTeX 数学公式渲染（`MathRenderer`）：复用 `SwiftMath` 实现带 LRU 缓存的矢量公式排版，支持行内（`$...$`）与块级（`$$...$$`）公式精确基线对齐、光标避让源码编辑以及语法错误优雅回退。
- 独立编辑语义引擎（`MarkdownTextActor`）：支持智能成对补全/吞吐与空配对退格、公式附件退格还原源码、列表/引用自动续行与有序列表自动重编号、两段式智能行首跳转（`⌘←`）以及段落上下移动（`⌥⌘↑` / `⌥⌘↓`）。
- 轻量级光标上下文通道（`EditorCursorContext`、`EditorBlockContext`、`EditorEntityInfo`、`EditorWikiLinkQuery`）及 `MDEditorProxy.onCursorContextChange` / `onEntityActivate` 回调，消除移动光标时触发全文 Markdown 重构的性能瓶颈。
- `EditorConfiguration` 新增 Ulysses 风格写作选项：行首语法标记悬挂缩进（`outdentSyntaxMarkers`）、基于临时属性的零重排专注模式（`focusMode`：关闭/当前句/当前段）、可调打字机锚点（`typewriterAnchor`：顶/中/底，滚轮浏览自动暂停）、当前行柔和背景高亮（`highlightCurrentLine`）及行内公式渲染开关（`renderMathInline`）。
- 新增 `[[WikiLink]]` 语法高亮，以及 `MDEditorProxy` 段落移动、公式插入与实体编辑触发方法。

### 修复
- 修复 `MarkdownConverter.toHTML(_:imageResolver:)` 输出 `.math` 节点时丢失 `$`/`$$` 定界符的问题，保证导出 HTML/PDF 时 KaTeX 正常渲染公式。
- 修复 `MarkdownHighlighter` 段落间距未接入 `EditorConfiguration.paragraphSpacing` 的问题，并支持编辑器聚焦状态下实时应用配置与主题切换而不覆盖正文输入。

## 2.2.0

### Upgraded
- Switched `MarkdownView` dependency from personal fork to upstream `Lakr233/MarkdownView` (v4.3.1), bringing incremental block fragment caching, streaming rendering improvements, macOS nested vertical scroll passthrough, and native table geometry adaptations.

---

### 升级
- 将 `MarkdownView` 依赖由个人 Fork 切换至上游官方仓库 `Lakr233/MarkdownView` (v4.3.1)，引入增量块级缓存、流式渲染优化、macOS 代码块滚轮事件穿透及原生自适应点阵表格布局。

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
