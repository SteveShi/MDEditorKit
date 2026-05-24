//
//  MDEditorView.swift
//  MDEditor
//

import AppKit
import Combine
import SwiftUI

/// MDEditor 模块的公开视图
/// 使用 TextKit 2 实现 Ulysses 风格的所见即所得编辑
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

            // 关键：不再暴力过滤，而是通过属性还原完整的 Markdown 源码
            // 这解决了由于图片替换为占位符导致的 SwiftUI 数据丢失且触发死循环的问题
            let reconstructed = reconstructMarkdown(from: textView.textStorage)

            if !isUpdatingFromSwiftUI && reconstructed != parent.text {
                parent.text = reconstructed
            }
            // 广播文本变化：宿主可在此挂载防抖自动保存、字数刷新、AI 监听等副作用。
            parent.proxy.onTextChange?(reconstructed)
        }

        /// 从富文本中还原 Markdown 源码，处理被替换为图片的附件。
        private func reconstructMarkdown(from textStorage: NSTextStorage?) -> String {
            guard let textStorage = textStorage else { return "" }
            var result = ""

            textStorage.enumerateAttributes(
                in: NSRange(location: 0, length: textStorage.length), options: []
            ) { attrs, range, _ in
                // 检查是否存在我们在 MarkdownHighlighter 中存入的源码备份
                if let source = attrs[NSAttributedString.Key("MarkdownSource")] as? String {
                    result += source
                } else {
                    result += (textStorage.string as NSString).substring(with: range)
                }
            }
            return result
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            textView.updateTypingAttributes()

            // 触发打字机模式滚动
            textView.scrollToCenter()

            // 向上层广播选区/光标变化（包含纯光标移动），用于上下文敏感 UI
            notifySelectionChange(in: textView)
        }

        /// 把当前选区与完整文本派发给 proxy.onSelectionChange。
        /// 注意：完整文本会通过 `reconstructMarkdown` 还原（与 textDidChange 走同一路径），
        /// 让外部拿到的总是 Markdown 源码而不是带占位符的富文本。
        func notifySelectionChange(in textView: MarkdownTextView) {
            guard let callback = parent.proxy.onSelectionChange else { return }
            let range = textView.selectedRange()
            let text = reconstructMarkdown(from: textView.textStorage)
            callback(range, text)
        }

        // MARK: - Proxy Sync

        func setupProxyActions() {
            guard let textView = textView else { return }

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
                // 走 insertText 让 NSTextView 处理撤销栈与代理回调
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

            // MARK: New APIs (1.8.0)

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
                guard let tv = textView,
                      let layoutManager = tv.layoutManager,
                      let textContainer = tv.textContainer else { return nil }
                let selected = tv.selectedRange()
                let caretRange = NSRange(location: selected.location, length: 0)
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: caretRange, actualCharacterRange: nil)
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                rect.origin.x += tv.textContainerOrigin.x
                rect.origin.y += tv.textContainerOrigin.y
                // textView → window
                let inView = tv.convert(rect, to: nil)
                return inView
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
                    // 末尾换行也算作一行的结束，与 wc -l 等工具一致
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

        // 视图挂载后立即派发一次初始选区，确保上层 UI（如上下文敏感工具栏）
        // 在没有任何用户输入前也能进入正确状态。
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            guard let coordinator = coordinator, let tv = coordinator.textView else { return }
            coordinator.notifySelectionChange(in: tv)
        }

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownTextView else { return }

        // 1. 焦点绝对同步锁定：如果用户正在打字（是第一响应者），绝对禁止强制同步文本、配置或主题
        // 这彻底防止了打字过程中因 State 更新导致的反向刷新、跳动和光标丢失
        if textView.window?.firstResponder == textView {
            return
        }

        // 2. 只有在非输入状态下，才同步配置与主题
        textView.applyConfiguration(configuration)
        textView.apply(theme: configuration.theme)

        // 3. 干净对比同步：剔除富文本占位符，避免冗余刷新
        let currentCleanText = textView.string.replacingOccurrences(of: "\u{FFFC}", with: "")

        if !context.coordinator.isUpdatingFromSwiftUI && currentCleanText != text {
            context.coordinator.isUpdatingFromSwiftUI = true

            // 备份光标
            let selectedRange = textView.selectedRange()

            // 执行同步
            textView.string = text
            textView.highlightMarkdown()

            // 恢复光标（如果在内容长度内）
            if selectedRange.location + selectedRange.length <= text.count {
                textView.setSelectedRange(selectedRange)
            }

            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }
}

// MARK: - MarkdownTextView

class MarkdownTextView: NSTextView {
    private lazy var highlighter = MarkdownHighlighter()
    private var isHighlighting = false
    private var currentConfiguration: EditorConfiguration?

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let string = string as? String, !string.isEmpty else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let pairs: [String: String] = ["*": "*", "_": "_", "`": "`", "~": "~", "[": "]", "(": ")"]
        if let pairEnd = pairs[string] {
            let range = selectedRange()
            if range.length > 0 {
                let selectedText = (self.string as NSString).substring(with: range)
                let wrapped = "\(string)\(selectedText)\(pairEnd)"
                super.insertText(wrapped, replacementRange: range)
                return
            } else {
                let fullPair = string == "~" ? "~~~~" : "\(string)\(pairEnd)"
                super.insertText(fullPair, replacementRange: range)
                let offset = string == "~" ? 2 : 1
                self.setSelectedRange(NSRange(location: range.location + offset, length: 0))
                return
            }
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func didChangeText() {
        super.didChangeText()
        if !hasMarkedText() && !isHighlighting {  // 锁住递归
            // 优先使用 textStorage 的 editedRange，它是最准确的变更范围
            // 如果不可用，回退到 rangeForUserTextChange
            let range = textStorage?.editedRange ?? rangeForUserTextChange

            // 确保 range 有效，否则全量高亮
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
        let lineRange = text.lineRange(for: range)

        highlighter.highlight(textStorage, in: lineRange)

        // 强力触发排版确认，确保 TextKit 2 即时同步
        if let layoutManager = self.layoutManager {
            layoutManager.ensureLayout(forCharacterRange: lineRange)
            layoutManager.invalidateDisplay(forCharacterRange: lineRange)
        }

        // 关键：在布局确认后再更新输入属性，确保光标继承最新的样式
        updateTypingAttributes()

        needsDisplay = true
    }

    func apply(theme: EditorTheme) {
        // 防抖：主题完全相同则不触发重绘
        guard highlighter.theme != theme else { return }

        highlighter.theme = theme
        backgroundColor = .clear
        insertionPointColor = theme.insertionPoint.nsColor
        highlightMarkdown()
    }

    /// 应用编辑器配置
    func applyConfiguration(_ config: EditorConfiguration) {
        let configChanged = currentConfiguration != config
        currentConfiguration = config

        // 同步字体和图片提供者
        highlighter.baseFont = config.nsFont
        highlighter.lineHeightMultiple = config.lineHeightMultiple
        highlighter.imageProvider = config.imageProvider

        // 更新边距
        textContainerInset = NSSize(
            width: config.horizontalPadding,
            height: config.verticalPadding
        )

        // 更新打字机模式状态
        if config.typewriterMode {
            // 允许垂直滚动超过内容高度，以便最后一行也能居中
            // 注意：这需要 textContainer 的高度只有在大量内容时才有效，
            // 也可以通过 contentInsets 实现
            let halfScreen = (enclosingScrollView?.bounds.height ?? 600) / 2
            enclosingScrollView?.contentInsets.bottom = halfScreen
        } else {
            enclosingScrollView?.contentInsets.bottom = config.verticalPadding
        }

        // 仅当配置真正变化时才强制刷新高亮
        if configChanged {
            highlightMarkdown()
            updateTypingAttributes()  // 确保光标样式同步
            needsDisplay = true
        }
    }

    func scrollToCenter() {
        guard let configuration = currentConfiguration, configuration.typewriterMode else { return }
        guard let layoutManager = layoutManager,
            let textContainer = textContainer,
            let scrollView = enclosingScrollView
        else { return }

        let selectedRange = selectedRange()
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: selectedRange, actualCharacterRange: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        let documentVisRect = scrollView.documentVisibleRect
        let height = documentVisRect.height

        if glyphRect.height > 0 {
            // 计算目标 Y 坐标，使光标位于视图中心
            let targetY = glyphRect.midY - height / 2.0
            // 确保不越界（虽然 contentInsets 允许越界，但 scrollToPoint 需要被 clipView 约束）
            // 在 macOS 中，NSClipView 会自动处理 bounds 约束，但我们需要确保逻辑正确
            let point = NSPoint(x: 0, y: targetY)  // 允许负值，ClipView 会处理

            // 只有当偏差较大时才滚动，避免抖动？不，打字机模式通常紧跟
            scrollView.contentView.animator().setBoundsOrigin(point)
            // 使用 animator 平滑滚动，或者直接 scrollToPoint
            // scrollView.contentView.scrollToPoint(point)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func updateTypingAttributes() {
        let range = selectedRange()
        let fallbackForeground = highlighter.foregroundNSColor

        if range.location > 0, let textStorage = textStorage {
            let prevCharRange = NSRange(location: range.location - 1, length: 1)
            let prevChar = (textStorage.string as NSString).substring(with: prevCharRange)

            // 回车后光标在新行开头时，不应继承上一行的样式（如标题字体）
            // 而是根据当前行的内容决定样式，空行则使用默认基础样式
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
                        attrs.removeValue(forKey: NSAttributedString.Key("MarkdownSource"))
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
            attrs.removeValue(forKey: NSAttributedString.Key("MarkdownSource"))
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

/// 对 `textView` 当前选中行集合统一加/减一层缩进。
/// 缩进单位：单个 Tab。反缩进时优先去掉一个前导 Tab；若行首为 2 或 4 个空格也接受。
@MainActor
fileprivate func applyIndent(to textView: NSTextView, outdent: Bool) {
    let ns = textView.string as NSString
    let selected = textView.selectedRange()
    let lineRange = ns.lineRange(for: selected)
    let block = ns.substring(with: lineRange)

    // 保留尾随换行，逐行处理
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
    // 重新选中处理过的行集合，便于继续 Tab/Shift-Tab
    let newLength = (newBlock as NSString).length
    textView.setSelectedRange(NSRange(location: lineRange.location, length: newLength))
}
