//
//  EditorCursorContext.swift
//  MDEditorKit
//
//  轻量级光标上下文与内联实体信息，供宿主 UI（快捷符号栏、实体编辑气泡、双向链接补全）
//  在不触发全文 reconstructMarkdown 的前提下实时响应。
//

import CoreGraphics
import Foundation

/// 光标或选区所在的块/行内语法上下文。
public enum EditorBlockContext: Sendable, Equatable, Hashable {
    /// 无选区，空行或普通段落。关联值为基于前文标题推荐的下一级标题（1...3）。
    case empty(suggestedHeadingLevel: Int)
    /// 无选区，光标位于标题行（1...6）。
    case headingLine(level: Int)
    /// 无选区，光标位于列表行（- / * / + / 1. / - [ ]）。
    case listLine
    /// 无选区，光标位于引用行（>）。
    case quoteLine
    /// 无选区，光标位于围栏代码块内（``` ... ```）。
    case codeBlock
    /// 无选区，光标位于 LaTeX 块级公式（$$ ... $$）内。
    case mathBlock
    /// 选中行内文本。
    case inlineText
    /// 选中整行或跨行。
    case fullLines
}

/// 可在气泡中交互编辑的 Markdown 实体类别。
public enum EditorEntityKind: String, Sendable, Equatable, Hashable {
    case link
    case image
    case inlineMath
    case displayMath
}

/// 位于光标或点击位置的 Markdown 实体快照。
public struct EditorEntityInfo: Sendable, Equatable, Hashable {
    public let kind: EditorEntityKind
    /// 该实体在当前 `NSTextStorage` 中的字符区间（附件占 1 字符，源码实体占完整长度）。
    public let range: NSRange
    /// 原始 Markdown 源码片段。
    public let source: String
    /// 主值：link 为显示文字，image 为 alt，math 为去除 `$`/`$$` 的 LaTeX 表达式。
    public let primaryText: String
    /// 副值：link 为 URL，image 为路径/URL，math 为空串。
    public let secondaryText: String
    /// 该实体在窗口坐标系内的锚点矩形（用于定位气泡）。
    public let frameInWindow: CGRect?

    public init(
        kind: EditorEntityKind,
        range: NSRange,
        source: String,
        primaryText: String,
        secondaryText: String = "",
        frameInWindow: CGRect? = nil
    ) {
        self.kind = kind
        self.range = range
        self.source = source
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.frameInWindow = frameInWindow
    }
}

/// 光标前方尚未闭合的 WikiLink（`[[query`）补全查询。
public struct EditorWikiLinkQuery: Sendable, Equatable, Hashable {
    /// 从 `[[` 开始到光标位置的区间（替换时覆盖该区间）。
    public let replaceRange: NSRange
    /// `[[` 后已输入的查询词。
    public let query: String
    /// 光标在窗口坐标系中的矩形。
    public let caretFrameInWindow: CGRect?

    public init(replaceRange: NSRange, query: String, caretFrameInWindow: CGRect? = nil) {
        self.replaceRange = replaceRange
        self.query = query
        self.caretFrameInWindow = caretFrameInWindow
    }
}

/// 每次选区或光标变化时发出的轻量级上下文快照。
public struct EditorCursorContext: Sendable, Equatable, Hashable {
    public let blockContext: EditorBlockContext
    public let selectedRange: NSRange
    public let hasSelection: Bool
    public let activeEntity: EditorEntityInfo?
    public let wikiLinkQuery: EditorWikiLinkQuery?

    public init(
        blockContext: EditorBlockContext = .empty(suggestedHeadingLevel: 1),
        selectedRange: NSRange = NSRange(location: 0, length: 0),
        hasSelection: Bool = false,
        activeEntity: EditorEntityInfo? = nil,
        wikiLinkQuery: EditorWikiLinkQuery? = nil
    ) {
        self.blockContext = blockContext
        self.selectedRange = selectedRange
        self.hasSelection = hasSelection
        self.activeEntity = activeEntity
        self.wikiLinkQuery = wikiLinkQuery
    }
}
