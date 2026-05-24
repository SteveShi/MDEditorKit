//
//  MDEditorProxy.swift
//  MDEditor
//
//  用于外部与 MDEditorView 进行交互的代理对象
//

import AppKit
import Combine
import Foundation

// MARK: - EditorStats

/// 编辑器文本统计快照。
/// 字段语义：
/// - `characterCount`：Swift `Character` 单位（grapheme cluster），与用户感知一致。
/// - `wordCount`：空白分隔的非空 token 数；对 CJK 单字符段落而言会偏小，UI 文案需提示。
/// - `lineCount`：以 `\n` 为分隔的逻辑行数；空文本返回 0。
public struct EditorStats: Equatable {
    public let characterCount: Int
    public let wordCount: Int
    public let lineCount: Int

    public init(characterCount: Int, wordCount: Int, lineCount: Int) {
        self.characterCount = characterCount
        self.wordCount = wordCount
        self.lineCount = lineCount
    }
}

// MARK: - Proxy

/// MDEditor 的交互代理
/// 通过此对象可以向编辑器发送指令，如插入文本、查找替换等
public class MDEditorProxy: ObservableObject {

    // MARK: - Actions (Internal use)

    internal var insertTextAction: ((String) -> Void)?
    internal var wrapSelectionAction: ((String, String) -> Void)?
    internal var getSelectedTextAction: (() -> String?)?
    internal var getSelectedRangeAction: (() -> NSRange)?
    internal var getFullTextAction: (() -> String)?
    internal var replaceRangeAction: ((NSRange, String) -> Void)?
    internal var setSelectedRangeAction: ((NSRange) -> Void)?
    internal var findNextAction: ((String) -> Void)?
    internal var findPreviousAction: ((String) -> Void)?
    internal var replaceAction: ((String, String) -> Void)?
    internal var replaceAllAction: ((String, String) -> Void)?
    internal var printAction: (() -> Void)?
    internal var setEditorThemeAction: ((EditorTheme) -> Void)?

    // —— 新增：行级 helpers
    internal var getCurrentLineRangeAction: (() -> NSRange)?
    internal var getCurrentLineTextAction: (() -> String)?
    internal var replaceCurrentLineAction: ((String) -> Void)?

    // —— 新增：undo / redo
    internal var undoAction: (() -> Void)?
    internal var redoAction: (() -> Void)?
    internal var canUndoAction: (() -> Bool)?
    internal var canRedoAction: (() -> Bool)?

    // —— 新增：焦点
    internal var focusAction: (() -> Void)?
    internal var resignFocusAction: (() -> Void)?

    // —— 新增：滚动
    internal var scrollRangeToVisibleAction: ((NSRange) -> Void)?
    internal var scrollToTopAction: (() -> Void)?
    internal var scrollToBottomAction: (() -> Void)?

    // —— 新增：光标矩形
    internal var caretFrameInWindowAction: (() -> CGRect?)?

    // —— 新增：选择辅助
    internal var selectAllAction: (() -> Void)?
    internal var selectLineAction: (() -> Void)?
    internal var selectParagraphAction: (() -> Void)?

    // —— 新增：统计
    internal var statsAction: (() -> EditorStats)?

    // —— 新增：附件 / 富文本导出
    internal var insertImageAttachmentAction: ((NSImage, String) -> Void)?
    internal var exportAttributedStringAction: (() -> NSAttributedString)?

    // —— 新增：缩进
    internal var indentSelectionAction: (() -> Void)?
    internal var outdentSelectionAction: (() -> Void)?

    // MARK: - Selection / Text Observation

    /// 编辑器选区或光标位置发生变化时回调。
    /// 调用线程：主线程。每次 `NSTextView` 的 `textViewDidChangeSelection` 都会触发，
    /// 包括纯光标移动（无选区）的情形——便于上层做上下文敏感的 UI 切换。
    ///
    /// - Parameter range: 当前选区；`length == 0` 表示纯光标。
    /// - Parameter text: 当前编辑器完整文本（已还原 Markdown 源）。
    public var onSelectionChange: ((NSRange, String) -> Void)?

    /// 编辑器文本发生变化时回调。
    /// 调用线程：主线程。SwiftUI `@Binding text` 写回同源；
    /// 适合做防抖自动保存、字数统计实时刷新、AI 助手输入监听。
    ///
    /// - Parameter text: 当前编辑器完整文本（已还原 Markdown 源）。
    public var onTextChange: ((String) -> Void)?

    // MARK: - Initializer

    public init() {}

    // MARK: - Basic Edits

    public func insert(_ text: String) {
        insertTextAction?(text)
    }

    public func wrapSelection(prefix: String, suffix: String) {
        wrapSelectionAction?(prefix, suffix)
    }

    public func getSelectedText() -> String? {
        getSelectedTextAction?()
    }

    /// 当前选区。视图未挂载时返回 `NSRange(location: 0, length: 0)`。
    public func getSelectedRange() -> NSRange {
        getSelectedRangeAction?() ?? NSRange(location: 0, length: 0)
    }

    /// 当前编辑器完整文本（已还原 Markdown 源）。视图未挂载时返回空串。
    public func getFullText() -> String {
        getFullTextAction?() ?? ""
    }

    /// 用 `replacement` 替换 `range` 范围内的文本。
    /// 用于行级 block 前缀切换等需要原子替换的场景。
    public func replace(range: NSRange, with replacement: String) {
        replaceRangeAction?(range, replacement)
    }

    /// 设置当前选区或光标位置。
    public func setSelectedRange(_ range: NSRange) {
        setSelectedRangeAction?(range)
    }

    // MARK: - Line Helpers

    /// 当前光标所在行的 `NSRange`（包含行尾换行符，若存在）。视图未挂载时返回零长 range。
    public func getCurrentLineRange() -> NSRange {
        getCurrentLineRangeAction?() ?? NSRange(location: 0, length: 0)
    }

    /// 当前光标所在行文本（含行尾换行符，若存在）。视图未挂载时返回空串。
    public func getCurrentLineText() -> String {
        getCurrentLineTextAction?() ?? ""
    }

    /// 用 `replacement` 替换当前光标所在行（行尾换行符由调用方决定是否保留）。
    public func replaceCurrentLine(with replacement: String) {
        replaceCurrentLineAction?(replacement)
    }

    // MARK: - Undo / Redo

    public func undo() { undoAction?() }
    public func redo() { redoAction?() }
    public var canUndo: Bool { canUndoAction?() ?? false }
    public var canRedo: Bool { canRedoAction?() ?? false }

    // MARK: - Focus

    /// 让编辑器成为第一响应者。
    public func focus() { focusAction?() }
    /// 放弃第一响应者身份。
    public func resignFocus() { resignFocusAction?() }

    // MARK: - Scroll

    public func scrollRangeToVisible(_ range: NSRange) { scrollRangeToVisibleAction?(range) }
    public func scrollToTop() { scrollToTopAction?() }
    public func scrollToBottom() { scrollToBottomAction?() }

    // MARK: - Caret Geometry

    /// 当前光标在所属窗口坐标系内的矩形（用于浮动气泡 / 内联补全弹层定位）。
    /// 视图未挂载或没有可定位的光标时返回 `nil`。
    public func caretFrameInWindow() -> CGRect? {
        caretFrameInWindowAction?()
    }

    // MARK: - Selection Helpers

    public func selectAll() { selectAllAction?() }
    /// 选中当前光标所在的整行（含行尾换行符，若存在）。
    public func selectLine() { selectLineAction?() }
    /// 选中当前光标所在的整段（由空行分隔）。
    public func selectParagraph() { selectParagraphAction?() }

    // MARK: - Stats

    /// 当前编辑器文本的统计快照。视图未挂载时返回全 0。
    public func stats() -> EditorStats {
        statsAction?() ?? EditorStats(characterCount: 0, wordCount: 0, lineCount: 0)
    }

    // MARK: - Attachments / Export

    /// 在当前光标处插入一张图片附件，写入 Markdown 形式 `![alt](...)`。
    /// 具体的资源命名、落盘位置由宿主提供的 `imageProvider` 决定；本 API 只负责注入 markdown 文本。
    public func insertImage(_ image: NSImage, altText: String = "") {
        insertImageAttachmentAction?(image, altText)
    }

    /// 导出当前编辑器内容的富文本（含语法高亮后的属性）。用于 RTF/PDF 导出。
    public func exportAttributedString() -> NSAttributedString {
        exportAttributedStringAction?() ?? NSAttributedString(string: "")
    }

    // MARK: - Indent

    /// 对当前选中行集合整体加一层缩进（按列表前缀使用 `\t`；空选时缩进当前行）。
    public func indentSelection() { indentSelectionAction?() }
    /// 对当前选中行集合整体减一层缩进（仅去掉一个前导 `\t` 或两个空格）。
    public func outdentSelection() { outdentSelectionAction?() }

    // MARK: - Find & Replace

    public func findNext(text: String) { findNextAction?(text) }
    public func findPrevious(text: String) { findPreviousAction?(text) }
    public func replace(search: String, with replacement: String) { replaceAction?(search, replacement) }
    public func replaceAll(search: String, with replacement: String) { replaceAllAction?(search, replacement) }

    // MARK: - Misc

    public func print() { printAction?() }
    public func setTheme(_ theme: EditorTheme) { setEditorThemeAction?(theme) }
}
