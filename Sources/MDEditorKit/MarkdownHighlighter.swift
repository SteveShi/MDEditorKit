//
//  MarkdownHighlighter.swift
//  MDEditor
//
//  TextKit 2 语法高亮器 - 实现 Ulysses 风格的 Markdown 渲染
//

import AppKit
import MarkdownParser

/// Markdown 语法高亮器
/// 使用正则表达式匹配 Markdown 语法并应用样式
public final class MarkdownHighlighter: @unchecked Sendable {

    // MARK: - Properties

    /// 基础字体
    public var baseFont: NSFont = NSFont.systemFont(ofSize: 15)

    /// 语法标记字体（淡化显示）
    public var syntaxFont: NSFont {
        NSFont.systemFont(ofSize: baseFont.pointSize * 0.85, weight: .light)
    }

    /// 当前主题。
    public var theme: EditorTheme = .default

    /// 行高倍数
    public var lineHeightMultiple: CGFloat = 1.5

    /// 图片提供者
    public var imageProvider: (@Sendable (String) -> NSImage?)?

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
        if let r = try? NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)([^\*\n]+?)(?<!\*)\*(?!\*)|(?<!_)(?<!\w)_(?!_)([^_\n]+?)(?<!_)(?<!\w)_(?!_)"#) {
            p.append((r, .italic))
        }

        // 行内代码 `code`
        if let r = try? NSRegularExpression(pattern: #"`([^`]*)`"#) {
            p.append((r, .inlineCode))
        }

        // 链接 [text](url)
        if let r = try? NSRegularExpression(pattern: #"(?<!!)\[([^\]]*)\]\(([^)]*)\)"#) {
            p.append((r, .link))
        }

        // 删除线 ~~text~~
        if let r = try? NSRegularExpression(pattern: #"~~([^\n]+?)~~"#) {
            p.append((r, .strikethrough))
        }

        // 引用块 > text
        if let r = try? NSRegularExpression(pattern: #"^>\s(.*)$"#, options: .anchorsMatchLines) {
            p.append((r, .blockquote))
        }

        // 任务列表与列表标记 - 或 1. 或 - [ ]
        if let r = try? NSRegularExpression(
            pattern: #"^(\s*)([-*+](\s+\[[ xX]\])?|\d+\.)\s"#, options: .anchorsMatchLines)
        {
            p.append((r, .listMarker))
        }

        // 图片 ![]()
        if let r = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) {
            p.append((r, .image))
        }

        return p
    }()

    private enum HighlightStyle {
        case heading, bold, italic, boldItalic, inlineCode, link, strikethrough, blockquote, listMarker, image, horizontalRule
    }

    // MARK: - Initializer

    public init() {}

    // MARK: - Public Methods

    /// 为给定文本应用 Markdown 高亮
    public func highlight(_ textStorage: NSTextStorage, in range: NSRange) {
        let textSnapshot = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: textSnapshot.length)
        let targetRange = NSIntersectionRange(range, fullRange)

        guard targetRange.length > 0 else { return }

        // 扩展到完整行范围，确保标题、列表等行首语法能被正确捕获
        let lineRange = textSnapshot.lineRange(for: targetRange)

        // 渲染锁：图片替换会改变长度，必须从后往前执行以保持索引有效
        var imageReplacements: [(NSRange, NSAttributedString)] = []

        textStorage.beginEditing()

        // 1. 重置视图基础样式，保护图片附件
        let baseStyle = createBaseParagraphStyle()

        var attachments: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { val, range, _ in
            if val != nil {
                attachments.append(
                    (range, textStorage.attributes(at: range.location, effectiveRange: nil)))
            }
        }

        textStorage.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: textColor,
                .paragraphStyle: baseStyle,
            ], range: lineRange)

        for (range, attrs) in attachments {
            textStorage.addAttributes(attrs, range: range)
        }

        let searchString = textSnapshot as String

        // 2. 第一阶段：扫描所有样式
        for (regex, style) in patterns {
            regex.enumerateMatches(in: searchString, options: [], range: lineRange) { match, _, _ in
                guard let match = match else { return }

                if style == .image {
                    if let attrString = self.createImageAttachmentString(
                        for: match, in: textSnapshot)
                    {
                        imageReplacements.append((match.range, attrString))
                    }
                } else {
                    self.applyStyle(style, to: textStorage, match: match, text: textSnapshot)
                }
            }
        }

        // 3. 第二阶段：逆序替换图片附件
        if !imageReplacements.isEmpty {
            for (replaceRange, attrString) in imageReplacements.reversed() {
                var isAlreadyRendered = false
                if replaceRange.length == 1 {
                    let currentAttrs = textStorage.attributes(
                        at: replaceRange.location, effectiveRange: nil)
                    if let currentSource = currentAttrs[NSAttributedString.Key("MarkdownSource")]
                        as? String,
                        let newSource = attrString.attribute(
                            NSAttributedString.Key("MarkdownSource"), at: 0, effectiveRange: nil)
                            as? String,
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

        applyParserBackedStyles(to: textStorage, lineRange: lineRange)

        textStorage.endEditing()
    }

    // MARK: - Public Helper Methods

    public var foregroundNSColor: NSColor { textColor }

    public func createBaseParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = 8
        return style
    }

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
        case .strikethrough:
            applyStrikethroughStyle(to: storage, match: match)
        case .blockquote:
            applyBlockquoteStyle(to: storage, match: match)
        case .listMarker:
            applyListMarkerStyle(to: storage, match: match)
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

        let headingFont: NSFont
        let boldDescriptor = scaledFont.fontDescriptor.withSymbolicTraits(.bold)
        headingFont =
            NSFont(descriptor: boldDescriptor, size: fontSize)
            ?? NSFont.boldSystemFont(ofSize: fontSize)

        let lineRange = text.lineRange(for: match.range)
        storage.addAttributes(
            [
                .font: headingFont,
                .foregroundColor: headingColor,
            ], range: lineRange)

        storage.addAttribute(.foregroundColor, value: syntaxColor, range: hashRange)
        storage.addAttribute(.font, value: syntaxFont, range: hashRange)
    }

    private func applyMarkerFade(to storage: NSTextStorage, fullRange: NSRange, markerLength: Int) {
        let startMarker = NSRange(location: fullRange.location, length: markerLength)
        let endMarker = NSRange(location: fullRange.location + fullRange.length - markerLength, length: markerLength)
        let attrs: [NSAttributedString.Key: Any] = [.font: syntaxFont, .foregroundColor: syntaxColor]
        storage.addAttributes(attrs, range: startMarker)
        storage.addAttributes(attrs, range: endMarker)
    }

    private func applyBoldStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        var contentRange = fullRange
        if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound && match.range(at: 1).length > 0 {
            contentRange = match.range(at: 1)
        }
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        storage.addAttributes([.font: boldFont, .foregroundColor: emphasisColor], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 2)
    }

    private func applyItalicStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        var contentRange = fullRange
        if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound && match.range(at: 1).length > 0 {
            contentRange = match.range(at: 1)
        } else if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound && match.range(at: 2).length > 0 {
            contentRange = match.range(at: 2)
        }

        // 尝试获取斜体字形；中文字体通常无斜体字形，convert 后返回原字体
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let hasTrueItalic = NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask)

        // CJK 字体无原生斜体时使用较大的 obliqueness 值使倾斜效果清晰可辨
        let obliquenessValue: Double = hasTrueItalic ? 0.0 : 0.3

        storage.addAttributes([
            .font: italicFont,
            .foregroundColor: emphasisColor,
            .obliqueness: obliquenessValue
        ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 1)
    }

    private func applyBoldItalicStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        var contentRange = fullRange
        if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound && match.range(at: 1).length > 0 {
            contentRange = match.range(at: 1)
        }

        let boldItalicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: [.boldFontMask, .italicFontMask])
        let hasTrueItalic = NSFontManager.shared.traits(of: boldItalicFont).contains(.italicFontMask)
        let obliquenessValue: Double = hasTrueItalic ? 0.0 : 0.3

        storage.addAttributes([
            .font: boldItalicFont,
            .foregroundColor: emphasisColor,
            .obliqueness: obliquenessValue
        ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 3)
    }

    private func applyInlineCodeStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        let contentRange = match.range(at: 1)
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
        storage.addAttributes([
            .font: monoFont,
            .foregroundColor: codeColor,
            .backgroundColor: codeBackground,
        ], range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 1)
    }

    private func applyLinkStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let textRange = match.range(at: 1)
        let urlRange = match.range(at: 2)

        storage.addAttributes([
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

    private func applyStrikethroughStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        let contentRange = match.range(at: 1)
        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
        applyMarkerFade(to: storage, fullRange: fullRange, markerLength: 2)
    }

    private func applyBlockquoteStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let fullRange = match.range
        storage.addAttribute(.foregroundColor, value: blockquoteColor, range: fullRange)

        let markerRange = NSRange(location: fullRange.location, length: 2)
        storage.addAttributes(
            [.font: syntaxFont, .foregroundColor: syntaxColor], range: markerRange)
    }

    private func applyListMarkerStyle(to storage: NSTextStorage, match: NSTextCheckingResult) {
        let markerRange = match.range(at: 2)
        storage.addAttributes(
            [.font: syntaxFont, .foregroundColor: syntaxColor], range: markerRange)
    }

    private func applyParserBackedStyles(to storage: NSTextStorage, lineRange: NSRange) {
        let text = (storage.string as NSString).substring(with: lineRange)
        let parser = MarkdownParser()
        let result = parser.parse(text)
        let ranges = parser.parseBlockRange(text)

        for (index, block) in result.document.enumerated() {
            guard index < ranges.count else { break }
            let relativeRange = ranges[index]

            let absoluteLocation = lineRange.location + text.distance(from: text.startIndex, to: relativeRange.startIndex)
            let absoluteLength = text.distance(from: relativeRange.startIndex, to: relativeRange.endIndex)
            let absoluteRange = NSRange(location: absoluteLocation, length: absoluteLength)

            guard absoluteRange.location != NSNotFound,
                  absoluteRange.location + absoluteRange.length <= storage.length else { continue }

            switch block {
            case .codeBlock:
                let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
                storage.addAttributes([
                    .backgroundColor: codeBlockBackground,
                    .font: monoFont,
                    .foregroundColor: codeColor
                ], range: absoluteRange)
            default:
                break
            }
        }
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
                NSAttributedString.Key("MarkdownSource"): fullSourceString,
            ], range: NSRange(location: 0, length: attrString.length))

        return attrString
    }
}
