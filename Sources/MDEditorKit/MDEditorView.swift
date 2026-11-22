//
//  MDEditorView.swift
//  MDEditor
//

import AppKit
import Combine
import SwiftUI

/// MDEditor 模块的公开视图
/// 实现 Ulysses 风格的所见即所得 Markdown 编辑体验
public struct MDEditorView: NSViewRepresentable {

    // MARK: - Properties

    @Binding public var text: String
    public var configuration: EditorConfiguration
    @ObservedObject public var proxy: MDEditorProxy
    @Environment(\.colorScheme) var colorScheme

    // MARK: - Initializer

    public init(text: Binding<String>, configuration: EditorConfiguration, proxy: MDEditorProxy) {
        self._text = text
        self.configuration = configuration
        self.proxy = proxy
    }

    // MARK: - Coordinator

    @MainActor
    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MDEditorView
        var isUpdatingFromSwiftUI = false
        weak var textView: MarkdownTextView?

        init(_ parent: MDEditorView) {
            self.parent = parent
            super.init()
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }

            let reconstructed = reconstructMarkdown(from: textView.textStorage)

            if !isUpdatingFromSwiftUI && reconstructed != parent.text {
                parent.text = reconstructed
            }
            parent.proxy.onTextChange?(reconstructed)
        }

        /// 从富文本中还原 Markdown 源码，处理被替换为图片或 LaTeX 数学公式的附件。
        func reconstructMarkdown(from textStorage: NSTextStorage?) -> String {
            guard let textStorage = textStorage else { return "" }
            var result = ""

            textStorage.enumerateAttributes(
                in: NSRange(location: 0, length: textStorage.length), options: []
            ) { attrs, range, _ in
                if let source = attrs[MarkdownTextActor.markdownSourceKey] as? String {
                    result += source
                } else {
                    result += (textStorage.string as NSString).substring(with: range)
                }
            }
            return result
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            textView.handleSelectionDidChange()

            // 触发打字机模式滚动（若用户正在手动滚轮浏览，内部自动跳过）
            textView.scrollToAnchorIfNeeded()

            // 向上层广播轻量上下文与（按需）选区变化
            notifySelectionChange(in: textView)
        }

        /// 派发轻量级 `onCursorContextChange`（零全文重构），
        /// 仅在宿主实际订阅了 `onSelectionChange` 时才还原全文字符串。
        func notifySelectionChange(in textView: MarkdownTextView) {
            if let contextCallback = parent.proxy.onCursorContextChange {
                let context = textView.currentCursorContext()
                contextCallback(context)
            }

            if let legacyCallback = parent.proxy.onSelectionChange {
                let range = textView.selectedRange()
                let text = reconstructMarkdown(from: textView.textStorage)
                legacyCallback(range, text)
            }
        }

        // MARK: - Proxy Sync

        func setupProxyActions() {
            guard let textView = textView else { return }

            textView.onEntityActivate = { [weak self] entity in
                self?.parent.proxy.onEntityActivate?(entity)
            }

            parent.proxy.insertTextAction = { [weak textView] text in
                guard let tv = textView else { return }
                let range = tv.selectedRange()
                tv.insertText(text, replacementRange: range)
            }

            parent.proxy.wrapSelectionAction = { [weak textView] prefix, suffix in
                guard let tv = textView else { return }
                let range = tv.selectedRange()
                let selectedText = (tv.string as NSString).substring(with: range)
                let newText = "\(prefix)\(selectedText)\(suffix)"
                tv.insertText(newText, replacementRange: range)
                if range.length == 0 {
                    let caret = range.location + (prefix as NSString).length
                    tv.setSelectedRange(NSRange(location: caret, length: 0))
                }
            }

            parent.proxy.getSelectedTextAction = { [weak textView] in
                guard let tv = textView else { return nil }
                let range = tv.selectedRange()
                return (tv.string as NSString).substring(with: range)
            }

            parent.proxy.getSelectedRangeAction = { [weak textView] in
                textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            }

            parent.proxy.getFullTextAction = { [weak self, weak textView] in
                guard let self = self, let tv = textView else { return "" }
                return self.reconstructMarkdown(from: tv.textStorage)
            }

            parent.proxy.replaceRangeAction = { [weak textView] range, replacement in
                guard let tv = textView else { return }
                let length = (tv.string as NSString).length
                let clamped = NSRange(
                    location: max(0, min(range.location, length)),
                    length: max(0, min(range.length, length - min(range.location, length)))
                )
                tv.insertText(replacement, replacementRange: clamped)
            }

            parent.proxy.setSelectedRangeAction = { [weak textView] range in
                guard let tv = textView else { return }
                let length = (tv.string as NSString).length
                let clamped = NSRange(
                    location: max(0, min(range.location, length)),
                    length: max(0, min(range.length, length - min(range.location, length)))
                )
                tv.setSelectedRange(clamped)
            }

            parent.proxy.findNextAction = { [weak textView] searchText in
                guard let tv = textView, !searchText.isEmpty else { return }
                let text = tv.string as NSString
                let currentLocation = tv.selectedRange().location + tv.selectedRange().length
                let searchRange = NSRange(
                    location: currentLocation, length: text.length - currentLocation)

                var foundRange = text.range(
                    of: searchText, options: .caseInsensitive, range: searchRange)
                if foundRange.location == NSNotFound {
                    foundRange = text.range(of: searchText, options: .caseInsensitive)
                }

                if foundRange.location != NSNotFound {
                    tv.setSelectedRange(foundRange)
                    tv.scrollRangeToVisible(foundRange)
                }
            }

            parent.proxy.findPreviousAction = { [weak textView] searchText in
                guard let tv = textView, !searchText.isEmpty else { return }
                let text = tv.string as NSString
                let currentLocation = tv.selectedRange().location
                let searchRange = NSRange(location: 0, length: currentLocation)

                var foundRange = text.range(
                    of: searchText, options: [.caseInsensitive, .backwards], range: searchRange)
                if foundRange.location == NSNotFound {
                    foundRange = text.range(
                        of: searchText, options: [.caseInsensitive, .backwards])
                }

                if foundRange.location != NSNotFound {
                    tv.setSelectedRange(foundRange)
                    tv.scrollRangeToVisible(foundRange)
                }
            }

            parent.proxy.replaceAction = { [weak textView] searchText, replaceText in
                guard let tv = textView else { return }
                let range = tv.selectedRange()
                let selectedText = (tv.string as NSString).substring(with: range)
                if selectedText.lowercased() == searchText.lowercased() {
                    tv.insertText(replaceText, replacementRange: range)
                }
            }

            parent.proxy.replaceAllAction = { [weak textView] searchText, replaceText in
                guard let tv = textView, !searchText.isEmpty else { return }
                let newString = tv.string.replacingOccurrences(
                    of: searchText, with: replaceText, options: .caseInsensitive)
                tv.string = newString
                tv.highlightMarkdown()
            }

            parent.proxy.printAction = { [weak textView] in
                textView?.printView(nil)
            }

            parent.proxy.setEditorThemeAction = { [weak textView] theme in
                textView?.apply(theme: theme)
            }

            // —— 行级 helpers
            parent.proxy.getCurrentLineRangeAction = { [weak textView] in
                guard let tv = textView else { return NSRange(location: 0, length: 0) }
                let ns = tv.string as NSString
                let loc = min(tv.selectedRange().location, ns.length)
                return ns.lineRange(for: NSRange(location: loc, length: 0))
            }
            parent.proxy.getCurrentLineTextAction = { [weak textView] in
                guard let tv = textView else { return "" }
                let ns = tv.string as NSString
                let loc = min(tv.selectedRange().location, ns.length)
                let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
                return ns.substring(with: lineRange)
            }
            parent.proxy.replaceCurrentLineAction = { [weak textView] replacement in
                guard let tv = textView else { return }
                let ns = tv.string as NSString
                let loc = min(tv.selectedRange().location, ns.length)
                let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
                tv.insertText(replacement, replacementRange: lineRange)
            }

            // —— Undo / Redo
            parent.proxy.undoAction = { [weak textView] in
                textView?.undoManager?.undo()
            }
            parent.proxy.redoAction = { [weak textView] in
                textView?.undoManager?.redo()
            }
            parent.proxy.canUndoAction = { [weak textView] in
                textView?.undoManager?.canUndo ?? false
            }
            parent.proxy.canRedoAction = { [weak textView] in
                textView?.undoManager?.canRedo ?? false
            }

            // —— 焦点
            parent.proxy.focusAction = { [weak textView] in
                guard let tv = textView, let window = tv.window else { return }
                window.makeFirstResponder(tv)
            }
            parent.proxy.resignFocusAction = { [weak textView] in
                guard let tv = textView, let window = tv.window else { return }
                if window.firstResponder === tv {
                    window.makeFirstResponder(nil)
                }
            }

            // —— 滚动
            parent.proxy.scrollRangeToVisibleAction = { [weak textView] range in
                textView?.scrollRangeToVisible(range)
            }
            parent.proxy.scrollToTopAction = { [weak textView] in
                textView?.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
            parent.proxy.scrollToBottomAction = { [weak textView] in
                guard let tv = textView else { return }
                let length = (tv.string as NSString).length
                tv.scrollRangeToVisible(NSRange(location: length, length: 0))
            }

            // —— 光标矩形（窗口坐标系）
            parent.proxy.caretFrameInWindowAction = { [weak textView] in
                guard let tv = textView else { return nil }
                return tv.caretBoundingFrameInWindow()
            }

            // —— 选择辅助
            parent.proxy.selectAllAction = { [weak textView] in
                textView?.selectAll(nil)
            }
            parent.proxy.selectLineAction = { [weak textView] in
                guard let tv = textView else { return }
                let ns = tv.string as NSString
                let loc = min(tv.selectedRange().location, ns.length)
                let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
                tv.setSelectedRange(lineRange)
            }
            parent.proxy.selectParagraphAction = { [weak textView] in
                guard let tv = textView else { return }
                let ns = tv.string as NSString
                let loc = min(tv.selectedRange().location, ns.length)
                let paragraphRange = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                tv.setSelectedRange(paragraphRange)
            }

            // —— 统计
            parent.proxy.statsAction = { [weak self, weak textView] in
                guard let self = self, let tv = textView else {
                    return EditorStats(characterCount: 0, wordCount: 0, lineCount: 0)
                }
                let text = self.reconstructMarkdown(from: tv.textStorage)
                let characterCount = text.count
                let wordCount = text.split(
                    whereSeparator: { $0.isWhitespace || $0.isNewline }
                ).count
                let lineCount: Int
                if text.isEmpty {
                    lineCount = 0
                } else {
                    lineCount = text.reduce(into: 1) { acc, ch in
                        if ch == "\n" { acc += 1 }
                    } - (text.last == "\n" ? 1 : 0)
                }
                return EditorStats(
                    characterCount: characterCount,
                    wordCount: wordCount,
                    lineCount: max(lineCount, text.isEmpty ? 0 : 1)
                )
            }

            // —— 插入图片
            parent.proxy.insertImageAttachmentAction = { [weak self, weak textView] image, altText in
                guard let self = self, let tv = textView else { return }
                guard let saver = self.parent.configuration.imageSaver,
                      let urlString = saver(image)
                else { return }
                let alt = altText.isEmpty ? "" : altText
                let markdown = "![\(alt)](\(urlString))"
                tv.insertText(markdown, replacementRange: tv.selectedRange())
            }

            // —— 导出富文本
            parent.proxy.exportAttributedStringAction = { [weak textView] in
                guard let storage = textView?.textStorage else {
                    return NSAttributedString(string: "")
                }
                return NSAttributedString(attributedString: storage)
            }

            // —— 缩进 / 反缩进
            parent.proxy.indentSelectionAction = { [weak textView] in
                guard let tv = textView else { return }
                applyIndent(to: tv, outdent: false)
            }
            parent.proxy.outdentSelectionAction = { [weak textView] in
                guard let tv = textView else { return }
                applyIndent(to: tv, outdent: true)
            }

            // —— 段落上下移动（⌥⌘↑ / ⌥⌘↓）
            parent.proxy.moveParagraphUpAction = { [weak textView] in
                textView?.moveCurrentParagraph(up: true)
            }
            parent.proxy.moveParagraphDownAction = { [weak textView] in
                textView?.moveCurrentParagraph(up: false)
            }

            // —— LaTeX 公式插入
            parent.proxy.insertInlineMathAction = { [weak textView] expr in
                guard let tv = textView else { return }
                let range = tv.selectedRange()
                let selected = (tv.string as NSString).substring(with: range)
                let body = !expr.isEmpty ? expr : selected
                if body.isEmpty {
                    tv.insertText("$$", replacementRange: range)
                    tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                } else {
                    tv.insertText("$\(body)$", replacementRange: range)
                }
            }
            parent.proxy.insertDisplayMathAction = { [weak textView] expr in
                guard let tv = textView else { return }
                let range = tv.selectedRange()
                let selected = (tv.string as NSString).substring(with: range)
                let body = !expr.isEmpty ? expr : selected
                let block = "$$\n\(body)\n$$"
                tv.insertText(block, replacementRange: range)
                if body.isEmpty {
                    tv.setSelectedRange(NSRange(location: range.location + 3, length: 0))
                }
            }

            // —— 激活当前实体气泡
            parent.proxy.activateEntityAtCaretAction = { [weak textView] in
                textView?.activateEntityAtCaret()
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - NSView Lifecycle

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let textView = MarkdownTextView(frame: .zero)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.backgroundColor = .clear

        scrollView.documentView = textView
        textView.string = text

        // 应用初始配置
        textView.applyConfiguration(configuration)
        textView.apply(theme: configuration.theme)

        context.coordinator.setupProxyActions()

        // 视图挂载后立即派发一次初始上下文，确保上层 UI 在无输入前就处于正确状态
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            guard let coordinator = coordinator, let tv = coordinator.textView else { return }
            coordinator.notifySelectionChange(in: tv)
        }

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownTextView else { return }

        // 始终允许同步视图配置与主题（例如通过菜单快捷键实时切换专注模式/打字机锚点/公式渲染），
        // 内部有严格的等值短路防抖，不会在无变化时触发刷新。
        textView.applyConfiguration(configuration)
        textView.apply(theme: configuration.theme)

        // 焦点输入锁定：用户正在打字时绝对禁止从 SwiftUI Binding 反向覆盖正文
        if textView.window?.firstResponder == textView {
            return
        }

        let currentReconstructed = context.coordinator.reconstructMarkdown(from: textView.textStorage)
        if !context.coordinator.isUpdatingFromSwiftUI && currentReconstructed != text {
            context.coordinator.isUpdatingFromSwiftUI = true

            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.highlightMarkdown()

            let maxLen = (textView.string as NSString).length
            let safeLoc = min(selectedRange.location, maxLen)
            let safeLen = min(selectedRange.length, maxLen - safeLoc)
            textView.setSelectedRange(NSRange(location: safeLoc, length: safeLen))

            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }
}

// MARK: - MarkdownTextView

class MarkdownTextView: NSTextView {
    private lazy var highlighter = MarkdownHighlighter()
    private let actor = MarkdownTextActor()
    private var isHighlighting = false
    private var currentConfiguration: EditorConfiguration?
    private var isUserScrollingManually = false
    private var lastSelectionLineRange: NSRange?

    var onEntityActivate: ((EditorEntityInfo) -> Void)?

    // MARK: - Editing Semantics Overrides

    override func insertText(_ string: Any, replacementRange: NSRange) {
        isUserScrollingManually = false
        if let str = string as? String, !str.isEmpty {
            let handled = actor.handleInsertText(str, replacementRange: replacementRange, in: self) {
                inserted, range in
                super.insertText(inserted, replacementRange: range)
            }
            if handled { return }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        isUserScrollingManually = false
        if actor.handleInsertNewline(in: self) {
            return
        }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        isUserScrollingManually = false
        if actor.handleDeleteBackward(in: self) {
            return
        }
        super.deleteBackward(sender)
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        if actor.handleMoveToBeginningOfLine(extendingSelection: false, in: self) {
            return
        }
        super.moveToBeginningOfLine(sender)
    }

    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        if actor.handleMoveToBeginningOfLine(extendingSelection: true, in: self) {
            return
        }
        super.moveToBeginningOfLineAndModifySelection(sender)
    }

    override func keyDown(with event: NSEvent) {
        isUserScrollingManually = false
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌥⌘↑ / ⌥⌘↓ 段落上下移动
        if flags == [.option, .command] {
            if event.keyCode == 126 { // Up Arrow
                if actor.moveParagraph(up: true, in: self) { return }
            } else if event.keyCode == 125 { // Down Arrow
                if actor.moveParagraph(up: false, in: self) { return }
            }
        }

        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > 0.5 {
            isUserScrollingManually = true
        }
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: localPoint)

        // 单击已渲染的数学公式/图片附件，或 Command+点击链接 → 触发内联实体编辑气泡
        if let storage = textStorage, charIndex < storage.length {
            let attrs = storage.attributes(at: charIndex, effectiveRange: nil)
            let isAttachmentEntity = attrs[MarkdownTextActor.markdownSourceKey] != nil
            let isCommandClick = event.modifierFlags.contains(.command)

            if isAttachmentEntity || isCommandClick {
                super.mouseDown(with: event)
                if let entity = actor.detectEntity(at: charIndex, in: self) {
                    onEntityActivate?(entity)
                }
                return
            }
        }

        super.mouseDown(with: event)
    }

    // MARK: - Current Line Highlight Background

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let config = currentConfiguration,
              config.highlightCurrentLine,
              selectedRange().length == 0,
              let layoutManager = layoutManager,
              let textContainer = textContainer
        else { return }

        let nsText = string as NSString
        let selLoc = min(selectedRange().location, nsText.length)

        var lineRect: NSRect = .zero
        if nsText.length == 0 {
            lineRect = layoutManager.extraLineFragmentRect
        } else if selLoc == nsText.length && nsText.substring(from: nsText.length - 1) == "\n" {
            lineRect = layoutManager.extraLineFragmentRect
        } else {
            let safeChar = min(selLoc, max(0, nsText.length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeChar)
            if glyphIndex < layoutManager.numberOfGlyphs {
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            }
        }

        guard lineRect.height > 0 else { return }
        let origin = textContainerOrigin
        let highlightRect = NSRect(
            x: origin.x - 8,
            y: lineRect.origin.y + origin.y,
            width: textContainer.containerSize.width + 16,
            height: lineRect.height
        )
        if highlightRect.intersects(rect) {
            let highlightColor = config.theme.foreground.nsColor.withAlphaComponent(0.045)
            highlightColor.setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: 5, yRadius: 5).fill()
        }
    }

    // MARK: - Text Change & Highlighting

    override func didChangeText() {
        super.didChangeText()
        if !hasMarkedText() && !isHighlighting {
            let range = textStorage?.editedRange ?? rangeForUserTextChange
            if range.location != NSNotFound {
                highlightMarkdown(in: range)
            } else {
                highlightMarkdown()
            }
        }
    }

    func highlightMarkdown() {
        guard let textStorage = textStorage else { return }
        highlightMarkdown(in: NSRange(location: 0, length: textStorage.length))
    }

    func highlightMarkdown(in range: NSRange) {
        guard let textStorage = textStorage, !hasMarkedText(), !isHighlighting else { return }

        isHighlighting = true
        defer { isHighlighting = false }

        let text = textStorage.string as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard safeRange.length > 0 || text.length == 0 else { return }

        let lineRange = text.length > 0 ? text.lineRange(for: safeRange) : NSRange(location: 0, length: 0)
        highlighter.highlight(textStorage, in: lineRange, activeSelection: selectedRange())

        let updatedLineRange = NSIntersectionRange(
            lineRange, NSRange(location: 0, length: textStorage.length)
        )
        if let layoutManager = self.layoutManager, updatedLineRange.length > 0 {
            layoutManager.ensureLayout(forCharacterRange: updatedLineRange)
            layoutManager.invalidateDisplay(forCharacterRange: updatedLineRange)
        }

        applyFocusMode()
        updateTypingAttributes()
        needsDisplay = true
    }

    /// 光标移动后处理：
    /// 1. 若光标刚离开某条含 `$...$` 的原始行，立刻刷新旧行以便将刚输完的 LaTeX 渲染为公式；
    /// 2. 刷新零重排专注模式淡化区与当前行高亮带；
    /// 3. 同步输入属性。
    func handleSelectionDidChange() {
        guard let textStorage = textStorage, !isHighlighting else { return }
        let nsText = textStorage.string as NSString
        let currentLoc = min(selectedRange().location, nsText.length)
        let currentLine = nsText.length > 0
            ? nsText.lineRange(for: NSRange(location: currentLoc, length: 0))
            : NSRange(location: 0, length: 0)

        // 当光标离开上一行且开启行内公式渲染时，若上一行含 `$` 则触发单行刷新完成渲染
        if let prevLine = lastSelectionLineRange,
           prevLine != currentLine,
           currentConfiguration?.renderMathInline == true,
           prevLine.location < nsText.length
        {
            let clampedPrev = NSIntersectionRange(prevLine, NSRange(location: 0, length: nsText.length))
            if clampedPrev.length > 0 {
                let prevText = nsText.substring(with: clampedPrev)
                if prevText.contains("$") {
                    highlightMarkdown(in: clampedPrev)
                }
            }
        }
        lastSelectionLineRange = currentLine

        applyFocusMode()
        updateTypingAttributes()
        if currentConfiguration?.highlightCurrentLine == true {
            needsDisplay = true
        }
    }

    // MARK: - Zero-Reflow Focus Mode

    func applyFocusMode() {
        guard let config = currentConfiguration,
              let storage = textStorage,
              let layoutManager = layoutManager
        else { return }

        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        // 先清除旧的临时前景色属性（绝不触发 NSTextStorage 修改或重排）
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        guard config.focusMode != .off else { return }

        let nsText = storage.string as NSString
        let sel = selectedRange()
        let activeRange = focusRange(for: sel, in: nsText, mode: config.focusMode)
        let dimmedColor = config.theme.foreground.nsColor.withAlphaComponent(0.28)

        if activeRange.location > 0 {
            let before = NSRange(location: 0, length: activeRange.location)
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dimmedColor, forCharacterRange: before)
        }
        let afterStart = NSMaxRange(activeRange)
        if afterStart < fullRange.length {
            let after = NSRange(location: afterStart, length: fullRange.length - afterStart)
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dimmedColor, forCharacterRange: after)
        }
    }

    private func focusRange(
        for selection: NSRange,
        in text: NSString,
        mode: EditorFocusMode
    ) -> NSRange {
        let clampedLoc = min(selection.location, max(0, text.length - 1))
        let probeRange = NSRange(location: clampedLoc, length: min(selection.length, text.length - clampedLoc))

        switch mode {
        case .off:
            return NSRange(location: 0, length: text.length)
        case .paragraph:
            return text.paragraphRange(for: probeRange)
        case .sentence:
            let paraRange = text.paragraphRange(for: probeRange)
            var matchedSentence = paraRange
            text.enumerateSubstrings(in: paraRange, options: [.bySentences, .substringNotRequired]) {
                _, subRange, enclosingRange, stop in
                if clampedLoc >= enclosingRange.location && clampedLoc <= NSMaxRange(enclosingRange) {
                    matchedSentence = subRange.length > 0 ? enclosingRange : paraRange
                    stop.pointee = true
                }
            }
            return matchedSentence
        }
    }

    // MARK: - Theme & Configuration

    func apply(theme: EditorTheme) {
        guard highlighter.theme != theme else { return }

        highlighter.theme = theme
        backgroundColor = .clear
        insertionPointColor = theme.insertionPoint.nsColor
        highlightMarkdown()
    }

    func applyConfiguration(_ config: EditorConfiguration) {
        let previous = currentConfiguration
        let configChanged = previous != config
        currentConfiguration = config

        let needsRehighlight = previous == nil
            || previous?.fontName != config.fontName
            || previous?.fontSize != config.fontSize
            || previous?.lineHeightMultiple != config.lineHeightMultiple
            || previous?.paragraphSpacing != config.paragraphSpacing
            || previous?.outdentSyntaxMarkers != config.outdentSyntaxMarkers
            || previous?.renderMathInline != config.renderMathInline
            || previous?.theme != config.theme

        highlighter.baseFont = config.nsFont
        highlighter.lineHeightMultiple = config.lineHeightMultiple
        highlighter.paragraphSpacing = config.paragraphSpacing
        highlighter.outdentSyntaxMarkers = config.outdentSyntaxMarkers
        highlighter.renderMathInline = config.renderMathInline
        highlighter.imageProvider = config.imageProvider

        // 水平边距结合 contentWidth 居中约束
        textContainerInset = NSSize(
            width: config.horizontalPadding,
            height: config.verticalPadding
        )

        // 打字机模式上下留白，确保首行与末行均可停靠到锚点
        if config.typewriterMode {
            let viewportHeight = enclosingScrollView?.bounds.height ?? 600
            let anchor = config.typewriterAnchor.fraction
            enclosingScrollView?.contentInsets.top = max(config.verticalPadding, viewportHeight * anchor * 0.5)
            enclosingScrollView?.contentInsets.bottom = viewportHeight * (1.0 - anchor) + 80
        } else {
            enclosingScrollView?.contentInsets.top = config.verticalPadding
            enclosingScrollView?.contentInsets.bottom = config.verticalPadding
        }

        if needsRehighlight {
            highlightMarkdown()
            updateTypingAttributes()
            needsDisplay = true
        } else if configChanged {
            applyFocusMode()
            if config.typewriterMode {
                isUserScrollingManually = false
                scrollToAnchorIfNeeded()
            }
            needsDisplay = true
        }
    }

    // MARK: - Enhanced Typewriter Scrolling

    func scrollToAnchorIfNeeded() {
        guard let configuration = currentConfiguration,
              configuration.typewriterMode,
              !isUserScrollingManually
        else { return }
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let scrollView = enclosingScrollView
        else { return }

        let sel = selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphRect.height > 0 else { return }

        let visibleHeight = scrollView.documentVisibleRect.height
        let anchorY = visibleHeight * configuration.typewriterAnchor.fraction
        let targetY = glyphRect.midY + textContainerOrigin.y - anchorY

        // 小于 2pt 偏差跳过，避免高频微抖动
        if abs(scrollView.contentView.bounds.origin.y - targetY) < 2.0 {
            return
        }

        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Helpers Exposed to Coordinator

    func currentCursorContext() -> EditorCursorContext {
        actor.analyzeCursorContext(
            in: self,
            fencedCodeRanges: highlighter.fencedCodeRanges,
            mathBlockRanges: highlighter.mathBlockRanges
        )
    }

    func caretBoundingFrameInWindow() -> CGRect? {
        let sel = selectedRange()
        return actor.boundingFrameInWindow(for: NSRange(location: sel.location, length: 0), in: self)
    }

    func moveCurrentParagraph(up: Bool) {
        actor.moveParagraph(up: up, in: self)
    }

    func activateEntityAtCaret() {
        let loc = selectedRange().location
        if let entity = actor.detectEntity(at: loc, in: self) {
            onEntityActivate?(entity)
        }
    }

    // MARK: - Typing Attributes

    func updateTypingAttributes() {
        let range = selectedRange()
        let fallbackForeground = highlighter.foregroundNSColor

        if range.location > 0, let textStorage = textStorage {
            let prevCharRange = NSRange(location: range.location - 1, length: 1)
            let prevChar = (textStorage.string as NSString).substring(with: prevCharRange)

            if prevChar == "\n" {
                if range.location < textStorage.length {
                    let currentCharRange = NSRange(location: range.location, length: 1)
                    let currentChar = (textStorage.string as NSString).substring(with: currentCharRange)
                    if currentChar != "\n" {
                        var attrs = textStorage.attributes(at: range.location, effectiveRange: nil)
                        if (attrs[.foregroundColor] as? NSColor)?.alphaComponent == 0.6 {
                            attrs[.foregroundColor] = fallbackForeground
                        }
                        attrs.removeValue(forKey: .attachment)
                        attrs.removeValue(forKey: MarkdownTextActor.markdownSourceKey)
                        attrs.removeValue(forKey: MarkdownTextActor.markdownEntityKindKey)
                        typingAttributes = attrs
                        return
                    }
                }
                let paraStyle = highlighter.createBaseParagraphStyle()
                typingAttributes = [
                    .font: highlighter.baseFont,
                    .paragraphStyle: paraStyle,
                    .foregroundColor: fallbackForeground,
                ]
                return
            }

            var attrs = textStorage.attributes(at: range.location - 1, effectiveRange: nil)
            if (attrs[.foregroundColor] as? NSColor)?.alphaComponent == 0.6 {
                attrs[.foregroundColor] = fallbackForeground
            }
            attrs.removeValue(forKey: .attachment)
            attrs.removeValue(forKey: MarkdownTextActor.markdownSourceKey)
            attrs.removeValue(forKey: MarkdownTextActor.markdownEntityKindKey)
            typingAttributes = attrs
            return
        }

        let paraStyle = highlighter.createBaseParagraphStyle()
        typingAttributes = [
            .font: highlighter.baseFont,
            .paragraphStyle: paraStyle,
            .foregroundColor: fallbackForeground,
        ]
    }
}

// MARK: - Indent Helpers

@MainActor
fileprivate func applyIndent(to textView: NSTextView, outdent: Bool) {
    let ns = textView.string as NSString
    let selected = textView.selectedRange()
    let lineRange = ns.lineRange(for: selected)
    let block = ns.substring(with: lineRange)

    var trailingNewline = ""
    var workingBlock = block
    if block.hasSuffix("\r\n") {
        trailingNewline = "\r\n"
        workingBlock = String(block.dropLast(2))
    } else if block.hasSuffix("\n") {
        trailingNewline = "\n"
        workingBlock = String(block.dropLast())
    }

    let lines = workingBlock.components(separatedBy: "\n")
    let newLines: [String] = lines.map { line in
        if outdent {
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
            if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
            return line
        } else {
            return "\t" + line
        }
    }
    let newBlock = newLines.joined(separator: "\n") + trailingNewline
    textView.insertText(newBlock, replacementRange: lineRange)
    let newLength = (newBlock as NSString).length
    textView.setSelectedRange(NSRange(location: lineRange.location, length: newLength))
}
