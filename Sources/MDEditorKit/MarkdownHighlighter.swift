//
//  MarkdownHighlighter.swift
//  MDEditor
//
//  Markdown 语法高亮与内联排版引擎：
//  - 支持行首语法标记悬挂缩进（Outdent Tags）
//  - 支持离线原生 LaTeX 数学公式渲染（$...$ / $$...$$）与光标避让编辑
//  - 维护围栏代码块与数学块区间缓存，供光标上下文分析零开销查询
//

import AppKit
internal import MarkdownParser

/// Markdown 语法高亮器
@MainActor
public final class MarkdownHighlighter {

    // MARK: - Properties

    /// 基础字体
    public var baseFont: NSFont = NSFont.systemFont(ofSize: 15)

    /// 语法标记字体（淡化显示）
    public var syntaxFont: NSFont {
        NSFont.systemFont(ofSize: baseFont.pointSize * 0.85, weight: .light)
    }

    /// 当前主题
    public var theme: EditorTheme = .default

    /// 行高倍数
    public var lineHeightMultiple: CGFloat = 1.5

    /// 段落间距
    public var paragraphSpacing: CGFloat = 8.0

    /// 是否将行首标记（# / > / -）悬挂缩进到正文左边界外
    public var outdentSyntaxMarkers: Bool = true

    /// 是否将 LaTeX 数学公式实时渲染为基线对齐的矢量附件
    public var renderMathInline: Bool = true

    /// 图片提供者
    public var imageProvider: (@Sendable (String) -> NSImage?)?

    /// 缓存的围栏代码块区间（供光标上下文分析零扫描复用）
    public private(set) var fencedCodeRanges: [NSRange] = []

    /// 缓存的块级公式区间（供光标上下文分析零扫描复用）
    public private(set) var mathBlockRanges: [NSRange] = []

    /// 悬挂缩进保留的左侧通道宽度
    private var outdentGutter: CGFloat {
        outdentSyntaxMarkers ? 28.0 : 0.0
    }

    // MARK: - Colors

    private var textColor: NSColor { theme.foreground.nsColor }
    private var headingColor: NSColor { theme.heading.nsColor }
    private var syntaxColor: NSColor { theme.syntaxMarker.nsColor }
    private var emphasisColor: NSColor { theme.emphasis.nsColor }
    private var linkColor: NSColor { theme.link.nsColor }
    private var codeColor: NSColor { theme.inlineCode.nsColor }
    private var codeBackground: NSColor { theme.inlineCodeBackground.nsColor }
    private var codeBlockBackground: NSColor { theme.codeBlockBackground.nsColor }
    private var blockquoteColor: NSColor { theme.blockquote.nsColor }

    // MARK: - Regex Patterns

    private lazy var patterns: [(regex: NSRegularExpression, style: HighlightStyle)] = {
        var p: [(NSRegularExpression, HighlightStyle)] = []

        // 标题 # Heading
        if let r = try? NSRegularExpression(pattern: #"(?m)^ *(#{1,6}) *(.*)$"#) {
            p.append((r, .heading))
        }

        // 分割线 --- 或 *** 或 ___
        if let r = try? NSRegularExpression(pattern: #"(?m)^ *(?:-{3,}|\*{3,}|_{3,}) *$"#) {
            p.append((r, .horizontalRule))
        }

        // 加粗斜体 ***text*** 或 ___text___（单行限制）
        if let r = try? NSRegularExpression(pattern: #"(?:\*\*\*|___)([^\n]+?)(?:\*\*\*|___)"#) {
            p.append((r, .boldItalic))
        }

        // 加粗 **text** 或 __text__（单行限制）
        if let r = try? NSRegularExpression(pattern: #"(?:\*\*|__)([^\n]+?)(?:\*\*|__)"#) {
            p.append((r, .bold))
        }

        // 斜体 *text* 或 _text_（单行限制，支持中英文斜体）
        if let r = try? NSRegularExpression(
            pattern: #"(?<!\*)\*(?!\*)([^\*\n]+?)(?<!\*)\*(?!\*)|(?<!_)(?<!\w)_(?!_)([^_\n]+?)(?<!_)(?<!\w)_(?!_)"#
        ) {
            p.append((r, .italic))
        }

        // 行内代码 `code`
        if let r = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#) {
            p.append((r, .inlineCode))
        }

        // 链接 [text](url)
        if let r = try? NSRegularExpression(pattern: #"(?<!!)\[([^\]]*)\]\(([^)]*)\)"#) {
            p.append((r, .link))
        }

        // WikiLink [[Target]] 或 [[Target|Alias]]
        if let r = try? NSRegularExpression(pattern: #"(?<!!)\[\[([^\[\]\n]+)\]\]"#) {
            p.append((r, .wikiLink))
        }

        // 删除线 ~~text~~
        if let r = try? NSRegularExpression(pattern: #"~~([^\n]+?)~~"#) {
            p.append((r, .strikethrough))
        }

        // 引用块 > text
        if let r = try? NSRegularExpression(pattern: #"^>\s?(.*)$"#, options: .anchorsMatchLines) {
            p.append((r, .blockquote))
        }

        // 任务列表与列表标记 - 或 1. 或 - [ ]
        if let r = try? NSRegularExpression(
            pattern: #"^([ \t]*)([-*+](?:[ \t]+\[[ xX]\])?|\d+\.)[ \t]+"#, options: .anchorsMatchLines
        ) {
            p.append((r, .listMarker))
        }

        // 图片 ![]()
        if let r = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) {
            p.append((r, .image))
        }

        return p
    }()

    private lazy var displayMathRegex = try? NSRegularExpression(
        pattern: #"(?s)\$\$(.+?)\$\$"#
    )

    private lazy var inlineMathRegex = try? NSRegularExpression(
        pattern: #"(?<!\\)(?<!\$)\$(?!\$)(?!\s)([^\n$]+?)(?<!\s)(?<!\\)\$(?!\$)"#
    )

    private lazy var inlineCodeRegex = try? NSRegularExpression(pattern: #"`[^`\n]+`"#)

    private enum HighlightStyle {
        case heading, bold, italic, boldItalic, inlineCode, link, wikiLink, strikethrough,
            blockquote, listMarker, image, horizontalRule
    }

    // MARK: - Initializer

    public init() {}

    // MARK: - Public Methods

    /// 为给定文本应用 Markdown 高亮。
    /// - Parameters:
    ///   - textStorage: 目标文本存储。
    ///   - range: 需要刷新的字符区间。
    ///   - activeSelection: 当前光标/选区；当光标正落在某条 LaTeX 公式内部时，保持源码高亮不强行替换为附件。
    public func highlight(
        _ textStorage: NSTextStorage,
        in range: NSRange,
        activeSelection: NSRange? = nil
    ) {
        let textSnapshot = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: textSnapshot.length)

        // 先刷新块级围栏缓存（O(N) 轻扫换行与标记行，耗时微秒级）
        refreshBlockCaches(in: textSnapshot)

        let targetRange = NSIntersectionRange(range, fullRange)
        guard targetRange.length > 0 else { return }

        // 扩展到完整行范围；如果命中跨行数学块，则扩展覆盖整个数学块
        var lineRange = textSnapshot.lineRange(for: targetRange)
        for mathRange in mathBlockRanges {
            if NSIntersectionRange(lineRange, mathRange).length > 0 {
                lineRange = NSUnionRange(lineRange, mathRange)
            }
        }
        lineRange = NSIntersectionRange(lineRange, fullRange)

        // 若关闭了行内公式渲染，先将范围内已渲染的数学附件还原为原始 LaTeX 源码
        if !renderMathInline {
            unwrapMathAttachments(in: textStorage, range: lineRange)
            let updatedSnapshot = textStorage.string as NSString
            let updatedFull = NSRange(location: 0, length: updatedSnapshot.length)
            lineRange = NSIntersectionRange(lineRange, updatedFull)
            if lineRange.length == 0 { return }
        }

        let currentSnapshot = textStorage.string as NSString
        var replacements: [(NSRange, NSAttributedString)] = []

        textStorage.beginEditing()

        // 1. 重置基础样式，同时双备份图片与数学附件属性
        let baseStyle = createBaseParagraphStyle()

        var attachments: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { val, attrRange, _ in
            if val != nil {
                attachments.append(
                    (attrRange, textStorage.attributes(at: attrRange.location, effectiveRange: nil))
                )
            }
        }

        textStorage.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: textColor,
                .paragraphStyle: baseStyle,
            ], range: lineRange)

        for (attrRange, attrs) in attachments {
            textStorage.addAttributes(attrs, range: attrRange)
        }

        let searchString = currentSnapshot as String

        // 2. 第一阶段：扫描普通 Markdown 样式与图片
        for (regex, style) in patterns {
            regex.enumerateMatches(in: searchString, options: [], range: lineRange) { match, _, _ in
                guard let match = match else { return }
                // 跳过位于围栏代码块内部的行内模式
                if self.isInsideRanges(match.range, ranges: self.fencedCodeRanges) {
                    return
                }
                if style == .image {
                    if let attrString = self.createImageAttachmentString(for: match, in: currentSnapshot) {
                        replacements.append((match.range, attrString))
                    }
                } else {
                    self.applyStyle(style, to: textStorage, match: match, text: currentSnapshot)
                }
            }
        }

        // 3. 扫描并处理 LaTeX 数学公式（$$...$$ 与 $...$）
        let inlineCodeRanges = collectInlineCodeRanges(in: searchString, range: lineRange)
        var handledMathRanges: [NSRange] = []

        if let displayRegex = displayMathRegex {
            displayRegex.enumerateMatches(in: searchString, options: [], range: lineRange) { match, _, _ in
                guard let match = match else { return }
                let fullMatch = match.range
                guard !self.isInsideRanges(fullMatch, ranges: self.fencedCodeRanges),
                      !self.isInsideRanges(fullMatch, ranges: inlineCodeRanges)
                else { return }

                handledMathRanges.append(fullMatch)
                let latex = currentSnapshot.substring(with: match.range(at: 1))
                let source = currentSnapshot.substring(with: fullMatch)
                let caretInside = self.isSelectionInside(activeSelection, range: fullMatch)

                if self.renderMathInline, !caretInside,
                   let attrString = self.createMathAttachmentString(
                       latex: latex, source: source, isDisplay: true)
                {
                    replacements.append((fullMatch, attrString))
                } else {
                    self.applyRawMathStyle(
                        to: textStorage, fullRange: fullMatch, delimiterLength: 2, isDisplay: true)
                }
            }
        }

        if let inlineRegex = inlineMathRegex {
            inlineRegex.enumerateMatches(in: searchString, options: [], range: lineRange) { match, _, _ in
                guard let match = match else { return }
                let fullMatch = match.range
                guard !self.isInsideRanges(fullMatch, ranges: self.fencedCodeRanges),
                      !self.isInsideRanges(fullMatch, ranges: inlineCodeRanges),
                      !self.isInsideRanges(fullMatch, ranges: handledMathRanges)
                else { return }

                let latex = currentSnapshot.substring(with: match.range(at: 1))
                // 过滤纯数字金额误判（例如 "$10 and $20"）
                if self.looksLikeCurrencyOnly(latex) { return }

                let source = currentSnapshot.substring(with: fullMatch)
                let caretInside = self.isSelectionInside(activeSelection, range: fullMatch)

                if self.renderMathInline, !caretInside,
                   let attrString = self.createMathAttachmentString(
                       latex: latex, source: source, isDisplay: false)
                {
                    replacements.append((fullMatch, attrString))
                } else {
                    self.applyRawMathStyle(
                        to: textStorage, fullRange: fullMatch, delimiterLength: 1, isDisplay: false)
                }
            }
        }

        // 4. 第二阶段：按 location 逆序执行破坏性附件替换（图片 + 数学公式）
        if !replacements.isEmpty {
            let sorted = replacements.sorted { $0.0.location > $1.0.location }
            var lastStart = Int.max
            for (replaceRange, attrString) in sorted {
                // 防止重叠替换导致区间越界
                guard NSMaxRange(replaceRange) <= lastStart,
                      NSMaxRange(replaceRange) <= textStorage.length
                else { continue }
                lastStart = replaceRange.location

                var isAlreadyRendered = false
                if replaceRange.length == 1 {
                    let currentAttrs = textStorage.attributes(at: replaceRange.location, effectiveRange: nil)
                    if let currentSource = currentAttrs[MarkdownTextActor.markdownSourceKey] as? String,
                       let newSource = attrString.attribute(
                           MarkdownTextActor.markdownSourceKey, at: 0, effectiveRange: nil) as? String,
                       currentSource == newSource
                    {
                        isAlreadyRendered = true
                    }
                }

                if !isAlreadyRendered {
                    textStorage.replaceCharacters(in: replaceRange, with: attrString)
                }
            }
        }

        // 5. 应用围栏代码块样式（重新夹紧 lineRange，因附件替换可能缩短了长度）
        let finalLength = textStorage.length
        let clampedFinalRange = NSIntersectionRange(
            lineRange, NSRange(location: 0, length: finalLength)
        )
        if clampedFinalRange.length > 0 {
            applyFencedCodeBlockStyles(to: textStorage, targetRange: clampedFinalRange)
        }

        textStorage.endEditing()

        // 附件替换可能改变了长度，刷新最终块缓存
        refreshBlockCaches(in: textStorage.string as NSString)
    }

    // MARK: - Public Helper Methods

    public var foregroundNSColor: NSColor { textColor }

    public func createBaseParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = paragraphSpacing
        style.headIndent = outdentGutter
        style.firstLineHeadIndent = outdentGutter
        return style
    }

    /// 将指定范围内所有已渲染的数学公式附件还原为原始 Markdown 源码。
    public func unwrapMathAttachments(in textStorage: NSTextStorage, range: NSRange) {
        let full = NSRange(location: 0, length: textStorage.length)
        let clamped = NSIntersectionRange(range, full)
        guard clamped.length > 0 else { return }

        var toRestore: [(NSRange, String)] = []
        textStorage.enumerateAttribute(
            MarkdownTextActor.markdownEntityKindKey, in: clamped, options: []
        ) { value, attrRange, _ in
            guard let kind = value as? String,
                  kind == EditorEntityKind.inlineMath.rawValue
                      || kind == EditorEntityKind.displayMath.rawValue,
                  let source = textStorage.attribute(
                      MarkdownTextActor.markdownSourceKey, at: attrRange.location, effectiveRange: nil
                  ) as? String
            else { return }
            toRestore.append((attrRange, source))
        }

        guard !toRestore.isEmpty else { return }
        textStorage.beginEditing()
        for (attrRange, source) in toRestore.reversed() {
            textStorage.replaceCharacters(in: attrRange, with: source)
        }
        textStorage.endEditing()
    }

    // MARK: - Block Caches (Fenced Code & Multi-Line Math)

    private func refreshBlockCaches(in text: NSString) {
        var codeRanges: [NSRange] = []
        var mathRanges: [NSRange] = []

        var codeStart: Int? = nil
        var mathStart: Int? = nil
        var pos = 0

        while pos < text.length {
            let lineRange = text.lineRange(for: NSRange(location: pos, length: 0))
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let start = codeStart {
                    codeRanges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
                    codeStart = nil
                } else if mathStart == nil {
                    codeStart = lineRange.location
                }
            } else if codeStart == nil && trimmed == "$$" {
                if let start = mathStart {
                    mathRanges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
                    mathStart = nil
                } else {
                    mathStart = lineRange.location
                }
            }

            pos = NSMaxRange(lineRange)
        }

        if let start = codeStart {
            codeRanges.append(NSRange(location: start, length: text.length - start))
        }
        if let start = mathStart {
            mathRanges.append(NSRange(location: start, length: text.length - start))
        }

        self.fencedCodeRanges = codeRanges
        self.mathBlockRanges = mathRanges
    }

    // MARK: - Style Application

    private func applyStyle(
        _ style: HighlightStyle, to storage: NSTextStorage, match: NSTextCheckingResult,
        text: NSString
    ) {
        switch style {
        case .heading:
            applyHeadingStyle(to: storage, match: match, text: text)
        case .bold:
            applyBoldStyle(to: storage, match: match)
        case .italic:
            applyItalicStyle(to: storage, match: match)
        case .boldItalic:
            applyBoldItalicStyle(to: storage, match: match)
        case .inlineCode:
            applyInlineCodeStyle(to: storage, match: match)
        case .link:
            applyLinkStyle(to: storage, match: match)
        case .wikiLink:
            applyWikiLinkStyle(to: storage, match: match)
        case .strikethrough:
            applyStrikethroughStyle(to: storage, match: match)
        case .blockquote:
            applyBlockquoteStyle(to: storage, match: match, text: text)
        case .listMarker:
            applyListMarkerStyle(to: storage, match: match, text: text)
        case .horizontalRule:
            storage.addAttributes([.foregroundColor: syntaxColor, .font: syntaxFont], range: match.range)
        case .image:
            break
        }
    }

    private func applyHeadingStyle(
        to storage: NSTextStorage, match: NSTextCheckingResult, text: NSString
    ) {
        let hashRange = match.range(at: 1)
        let level = hashRange.length

        let multipliers: [CGFloat] = [2.0, 1.7, 1.5, 1.3, 1.2, 1.1]
        let fontSize = baseFont.pointSize * multipliers[min(level - 1, 5)]

        let scaledFont =
            NSFont(descriptor: baseFont.fontDescriptor, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        let boldDescriptor = scaledFont.fontDescriptor.withSymbolicTraits(.bold)
        let headingFont =
            NSFont(descriptor: boldDescriptor, size: fontSize)
            ?? NSFont.boldSystemFont(ofSize: fontSize)

        let lineRange = text.lineRange(for: match.range)
        let paraStyle = createBaseParagraphStyle()

        if outdentSyntaxMarkers {
            let contentRange = match.range(at: 2)
            let prefixLen = max(hashRange.length, contentRange.location - lineRange.location)
            let prefixString = text.substring(with: NSRange(location: lineRange.location, length: prefixLen))
            let markerWidth = (prefixString as NSString).size(withAttributes: [.font: syntaxFont]).width
            paraStyle.headIndent = outdentGutter
            paraStyle.firstLineHeadIndent = max(0, outdentGutter - markerWidth)
        }

        storage.addAttributes(
            [
                .font: headingFont,
                .foregroundColor: headingColor,
                .paragraphStyle: paraStyle,
            ], range: lineRange)

        storage.addAttribute(.foregroundColor, value: syntaxColor, range: hashRange)
        storage.addAttribute(.font, value: syntaxFont, range: hashRange)
    }

    private func applyMarkerFade(to storage: NSTextStorage, fullRange: NSRange, markerLength: Int) {
        let startMarker = NSRange(location: fullRange.location, length: markerLength)
        let endMarker = NSRange(
            location: fullRange.location + fullRange.length - markerLength, length: markerLength
        )
        let attrs: [NSAttributedString.Key: Any] = [.font: syntaxFont, .foregroundColor: syntaxColor]
        storage.addAttributes(attrs, range: startMarker)
        storage.addAttributes(attrs, range: endMarker)
    }

    private func applyBoldStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        var contentRange = fullRange
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound, match.range(at: 1).length > 0 {
            contentRange = match.range(at: 1)
        }
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        storage.addAttributes([.font: boldFont, .foregroundColor: emphasisColor], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 2)
    }

    private func applyItalicStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        var contentRange = fullRange
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound, match.range(at: 1).length > 0 {
            contentRange = match.range(at: 1)
        } else if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound, match.range(at: 2).length > 0 {
            contentRange = match.range(at: 2)
        }

        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let hasTrueItalic = NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask)
        let obliquenessValue: Double = hasTrueItalic ? 0.0 : 0.3

        storage.addAttributes(
            [
                .font: italicFont,
                .foregroundColor: emphasisColor,
                .obliqueness: obliquenessValue,
            ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 1)
    }

    private func applyBoldItalicStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        var contentRange = fullRange
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound, match.range(at: 1).length > 0 {
            contentRange = match.range(at: 1)
        }

        let boldItalicFont = NSFontManager.shared.convert(
            baseFont, toHaveTrait: [.boldFontMask, .italicFontMask]
        )
        let hasTrueItalic = NSFontManager.shared.traits(of: boldItalicFont).contains(.italicFontMask)
        let obliquenessValue: Double = hasTrueItalic ? 0.0 : 0.3

        storage.addAttributes(
            [
                .font: boldItalicFont,
                .foregroundColor: emphasisColor,
                .obliqueness: obliquenessValue,
            ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 3)
    }

    private func applyInlineCodeStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        let contentRange = match.range(at: 1)
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
        storage.addAttributes(
            [
                .font: monoFont,
                .foregroundColor: codeColor,
                .backgroundColor: codeBackground,
            ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 1)
    }

    private func applyLinkStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let textRange = match.range(at: 1)
        let urlRange = match.range(at: 2)

        storage.addAttributes(
            [
                .foregroundColor: linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: textRange)

        let bracketStart = NSRange(location: match.range.location, length: 1)
        let bracketEnd = NSRange(location: textRange.location + textRange.length, length: 2)
        let closeParen = NSRange(location: urlRange.location + urlRange.length, length: 1)

        let syntaxAttrs: [NSAttributedString.Key: Any] = [.font: syntaxFont, .foregroundColor: syntaxColor]
        storage.addAttributes(syntaxAttrs, range: bracketStart)
        storage.addAttributes(syntaxAttrs, range: bracketEnd)
        storage.addAttributes(syntaxAttrs, range: urlRange)
        storage.addAttributes(syntaxAttrs, range: closeParen)
    }

    private func applyWikiLinkStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        let contentRange = match.range(at: 1)
        storage.addAttributes(
            [
                .foregroundColor: linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 2)
    }

    private func applyStrikethroughStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        let contentRange = match.range(at: 1)
        storage.addAttribute(
            .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange
        )
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 2)
    }

    private func applyBlockquoteStyle(
        to storage: NSTextStorage, match: NSTextCheckingResult, text: NSString
    ) {
        let fullRange = match.range
        let lineRange = text.lineRange(for: fullRange)
        let paraStyle = createBaseParagraphStyle()
        if outdentSyntaxMarkers {
            let markerWidth = ("> " as NSString).size(withAttributes: [.font: syntaxFont]).width
            paraStyle.headIndent = outdentGutter
            paraStyle.firstLineHeadIndent = max(0, outdentGutter - markerWidth)
        }

        storage.addAttributes(
            [
                .foregroundColor: blockquoteColor,
                .paragraphStyle: paraStyle,
            ], range: lineRange)

        let markerLen = min(2, fullRange.length)
        let markerRange = NSRange(location: fullRange.location, length: markerLen)
        storage.addAttributes([.font: syntaxFont, .foregroundColor: syntaxColor], range: markerRange)
    }

    private func applyListMarkerStyle(
        to storage: NSTextStorage, match: NSTextCheckingResult, text: NSString
    ) {
        let indentRange = match.range(at: 1)
        let markerRange = match.range(at: 2)
        storage.addAttributes([.font: syntaxFont, .foregroundColor: syntaxColor], range: markerRange)

        if outdentSyntaxMarkers {
            let lineRange = text.lineRange(for: match.range)
            let indentStr = text.substring(with: indentRange)
            let extraIndent = CGFloat(indentStr.reduce(0) { $0 + ($1 == "\t" ? 20 : 8) })
            let fullMarkerStr = text.substring(
                with: NSRange(
                    location: markerRange.location,
                    length: NSMaxRange(match.range) - markerRange.location
                )
            )
            let markerWidth = (fullMarkerStr as NSString).size(withAttributes: [.font: syntaxFont]).width

            let paraStyle = createBaseParagraphStyle()
            paraStyle.headIndent = outdentGutter + extraIndent
            paraStyle.firstLineHeadIndent = max(0, outdentGutter + extraIndent - markerWidth)
            storage.addAttribute(.paragraphStyle, value: paraStyle, range: lineRange)
        }
    }

    private func applyRawMathStyle(
        to storage: NSTextStorage,
        fullRange: NSRange,
        delimiterLength: Int,
        isDisplay: Bool
    ) {
        guard fullRange.length >= delimiterLength * 2 else { return }
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular)
        let contentRange = NSRange(
            location: fullRange.location + delimiterLength,
            length: fullRange.length - delimiterLength * 2
        )
        storage.addAttributes(
            [
                .font: monoFont,
                .foregroundColor: linkColor,
                .backgroundColor: isDisplay ? codeBlockBackground : codeBackground,
            ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: delimiterLength)
    }

    private func applyFencedCodeBlockStyles(to storage: NSTextStorage, targetRange: NSRange) {
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
        let textSnapshot = storage.string as NSString

        // 优先用缓存的围栏代码块区间着色（支持跨行大代码块增量刷新）
        for codeRange in fencedCodeRanges {
            let overlap = NSIntersectionRange(codeRange, targetRange)
            guard overlap.length > 0, NSMaxRange(overlap) <= storage.length else { continue }
            storage.addAttributes(
                [
                    .backgroundColor: codeBlockBackground,
                    .font: monoFont,
                    .foregroundColor: codeColor,
                ], range: overlap)

            // 淡化首尾 ``` 围栏行
            let firstLine = textSnapshot.lineRange(for: NSRange(location: codeRange.location, length: 0))
            let firstOverlap = NSIntersectionRange(firstLine, overlap)
            if firstOverlap.length > 0 {
                storage.addAttribute(.foregroundColor, value: syntaxColor, range: firstOverlap)
            }
            if codeRange.length > firstLine.length {
                let lastLoc = max(codeRange.location, NSMaxRange(codeRange) - 1)
                let lastLine = textSnapshot.lineRange(for: NSRange(location: lastLoc, length: 0))
                let lastText = textSnapshot.substring(with: lastLine).trimmingCharacters(in: .whitespacesAndNewlines)
                if lastText.hasPrefix("```") || lastText.hasPrefix("~~~") {
                    let lastOverlap = NSIntersectionRange(lastLine, overlap)
                    if lastOverlap.length > 0 {
                        storage.addAttribute(.foregroundColor, value: syntaxColor, range: lastOverlap)
                    }
                }
            }
        }
    }

    // MARK: - Attachment Factories

    private func createMathAttachmentString(
        latex: String, source: String, isDisplay: Bool
    ) -> NSAttributedString? {
        guard let rendered = MathRenderer.shared.render(
            latex: latex,
            fontSize: baseFont.pointSize,
            textColor: textColor,
            isDisplay: isDisplay
        ) else {
            return nil
        }

        let attachment = NSTextAttachment()
        attachment.image = rendered.image
        let size = rendered.image.size
        // 精确按 descent 下移基线，使行内公式与中英文基线自然齐平
        let yOffset = isDisplay ? -4.0 : -rendered.descent
        attachment.bounds = CGRect(x: 0, y: yOffset, width: size.width, height: size.height)

        let paraStyle = createBaseParagraphStyle()
        if isDisplay {
            paraStyle.alignment = .center
        }

        let attrString = NSMutableAttributedString(attachment: attachment)
        attrString.addAttributes(
            [
                .font: baseFont,
                .foregroundColor: textColor,
                .paragraphStyle: paraStyle,
                MarkdownTextActor.markdownSourceKey: source,
                MarkdownTextActor.markdownEntityKindKey: (
                    isDisplay ? EditorEntityKind.displayMath.rawValue : EditorEntityKind.inlineMath.rawValue
                ),
            ],
            range: NSRange(location: 0, length: attrString.length)
        )
        return attrString
    }

    private func createImageAttachmentString(
        for match: NSTextCheckingResult, in text: NSString
    ) -> NSAttributedString? {
        let fullRange = match.range
        let fullSourceString = text.substring(with: fullRange)
        let pathRange = match.range(at: 2)
        let path = text.substring(with: pathRange)

        var image: NSImage?
        if let provider = imageProvider {
            image = provider(path)
        }

        if image == nil {
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            } else {
                let fileURL = URL(fileURLWithPath: path)
                image = NSImage(contentsOf: fileURL)
            }
        }

        guard let validImage = image else { return nil }

        let attachment = NSTextAttachment()
        attachment.image = validImage

        let maxImageWidth: CGFloat = 500
        let imageSize = validImage.size

        if imageSize.width > maxImageWidth {
            let aspectRatio = imageSize.height / imageSize.width
            attachment.bounds = CGRect(
                x: 0, y: 0, width: maxImageWidth, height: maxImageWidth * aspectRatio)
        } else {
            attachment.bounds = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        }

        let attrString = NSMutableAttributedString(attachment: attachment)
        attrString.addAttributes(
            [
                .font: baseFont,
                .foregroundColor: textColor,
                MarkdownTextActor.markdownSourceKey: fullSourceString,
                MarkdownTextActor.markdownEntityKindKey: EditorEntityKind.image.rawValue,
            ], range: NSRange(location: 0, length: attrString.length))

        return attrString
    }

    // MARK: - Helpers

    private func collectInlineCodeRanges(in string: String, range: NSRange) -> [NSRange] {
        guard let regex = inlineCodeRegex else { return [] }
        return regex.matches(in: string, options: [], range: range).map(\.range)
    }

    private func isInsideRanges(_ candidate: NSRange, ranges: [NSRange]) -> Bool {
        for r in ranges {
            if NSIntersectionRange(candidate, r).length > 0 {
                return true
            }
        }
        return false
    }

    private func isSelectionInside(_ selection: NSRange?, range: NSRange) -> Bool {
        guard let sel = selection else { return false }
        if sel.length == 0 {
            return sel.location >= range.location && sel.location <= NSMaxRange(range)
        }
        return NSIntersectionRange(sel, range).length > 0
    }

    private func looksLikeCurrencyOnly(_ inner: String) -> Bool {
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        // 若以数字开头且包含大量普通英文单词（无反斜杠/运算符/上下标），大概率是 "$5 and $10" 这种货币表达
        let hasMathCue = trimmed.contains("\\") || trimmed.contains("^") || trimmed.contains("_")
            || trimmed.contains("=") || trimmed.contains("+") || trimmed.contains("-")
            || trimmed.contains("*") || trimmed.contains("/") || trimmed.contains("{")
        if !hasMathCue && trimmed.contains(" ") {
            if let first = trimmed.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
                return true
            }
        }
        return false
    }
}
