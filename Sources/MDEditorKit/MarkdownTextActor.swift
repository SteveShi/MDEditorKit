//
//  MarkdownTextActor.swift
//  MDEditorKit
//
//  独立的 Markdown 编辑语义与上下文分析引擎（参考 Ulysses ULTextActor 架构）。
//  收拢智能成对补全/吞吐、列表续行与自动重编号、两段式行首跳转、段落上下移动，
//  以及零全文重构的光标上下文 / 实体 / WikiLink 查询分析。
//

import AppKit
import Foundation

@MainActor
final class MarkdownTextActor {

    // MARK: - Constants

    static let markdownSourceKey = NSAttributedString.Key("MarkdownSource")
    static let markdownEntityKindKey = NSAttributedString.Key("MarkdownEntityKind")

    private static let autoPairs: [String: String] = [
        "*": "*",
        "_": "_",
        "`": "`",
        "~": "~",
        "[": "]",
        "(": ")",
        "$": "$",
    ]

    private static let closingPairs: Set<String> = ["*", "_", "`", "~", "]", ")", "$"]

    // MARK: - Smart Insert (Auto-Pairing & Overtype)

    /// 处理单字符输入：支持选区包裹、闭合符吞吐（overtype）与成对自动补全。
    /// 返回 `true` 表示事件已消费，无需再调用 `super.insertText`。
    func handleInsertText(
        _ text: String,
        replacementRange: NSRange,
        in textView: NSTextView,
        callSuper: (String, NSRange) -> Void
    ) -> Bool {
        // 仅拦截单字符标点输入，避免干扰中文输入法组词与粘贴多字符
        guard text.count == 1, !textView.hasMarkedText() else { return false }

        let nsText = textView.string as NSString
        let selection = replacementRange.location == NSNotFound
            ? textView.selectedRange()
            : replacementRange

        // 1. 有选区且输入左配对符号：包裹选区
        if selection.length > 0, let pairEnd = Self.autoPairs[text] {
            let clamped = clamp(selection, to: nsText.length)
            let selectedText = nsText.substring(with: clamped)
            let wrapped = "\(text)\(selectedText)\(pairEnd)"
            callSuper(wrapped, clamped)
            // 选中包裹后的内部文本，方便继续叠加样式
            textView.setSelectedRange(
                NSRange(location: clamped.location + (text as NSString).length, length: clamped.length)
            )
            return true
        }

        guard selection.length == 0, selection.location <= nsText.length else { return false }

        // 2. Overtype（吞吐）：如果紧邻光标右侧正是相同的闭合符，直接跳过而非重复插入
        if Self.closingPairs.contains(text), selection.location < nsText.length {
            let nextChar = nsText.substring(with: NSRange(location: selection.location, length: 1))
            if nextChar == text {
                // 特例：在 `$$` 开头（左侧已有一个 `$` 且右侧有一个 `$`）时，允许输入第二个 `$` 形成 `$$|$$`
                let isExpandingToDoubleDollar: Bool = {
                    guard text == "$", selection.location > 0 else { return false }
                    let prevChar = nsText.substring(
                        with: NSRange(location: selection.location - 1, length: 1)
                    )
                    // 仅当左侧是单个 `$`（前面不是 `$`）时才扩展成 `$$|$$`
                    let prevPrevIsDollar = selection.location >= 2
                        && nsText.substring(with: NSRange(location: selection.location - 2, length: 1)) == "$"
                    return prevChar == "$" && !prevPrevIsDollar
                }()

                // 同理：在 `*|`* 内再敲 `*` 扩展成 `**|**`
                let isExpandingToBoldStar: Bool = {
                    guard text == "*", selection.location > 0 else { return false }
                    let prevChar = nsText.substring(
                        with: NSRange(location: selection.location - 1, length: 1)
                    )
                    let prevPrevIsStar = selection.location >= 2
                        && nsText.substring(with: NSRange(location: selection.location - 2, length: 1)) == "*"
                    return prevChar == "*" && !prevPrevIsStar
                }()

                if isExpandingToDoubleDollar {
                    callSuper("$$", selection)
                    textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
                    return true
                }
                if isExpandingToBoldStar {
                    callSuper("**", selection)
                    textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
                    return true
                }

                // 若光标前并非空白（或这是明确的右括号 `]` / `)`），直接跳过闭合符
                let isExplicitCloser = (text == "]" || text == ")")
                let prevIsNonSpace: Bool = {
                    guard selection.location > 0 else { return false }
                    let prev = nsText.substring(with: NSRange(location: selection.location - 1, length: 1))
                    return prev != " " && prev != "\t" && prev != "\n" && prev != text
                }()

                if isExplicitCloser || prevIsNonSpace {
                    textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
                    return true
                }
            }
        }

        // 3. 无选区自动成对补全
        if let pairEnd = Self.autoPairs[text] {
            // 输入 `$` 若右侧紧跟数字（如 `$50`）不自动补全，避免干扰金额输入
            if text == "$", selection.location < nsText.length {
                let next = nsText.substring(with: NSRange(location: selection.location, length: 1))
                if let scalar = next.unicodeScalars.first, CharacterSet.decimalDigits.contains(scalar) {
                    return false
                }
            }
            // 输入 `_` 若左侧紧跟字母数字（如 snake_case）不自动补全
            if text == "_", selection.location > 0 {
                let prev = nsText.substring(with: NSRange(location: selection.location - 1, length: 1))
                if let scalar = prev.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
                    return false
                }
            }

            let fullPair = (text == "~") ? "~~~~" : "\(text)\(pairEnd)"
            let offset = (text == "~") ? 2 : 1
            callSuper(fullPair, selection)
            textView.setSelectedRange(NSRange(location: selection.location + offset, length: 0))
            return true
        }

        return false
    }

    // MARK: - Smart Delete Backward

    /// 智能退格：
    /// 1. 光标紧跟在已渲染的数学公式附件后按退格，将其还原为可编辑的原始 LaTeX 源码；
    /// 2. 光标位于空配对符号中间（如 `(|)`、`[|]`、`$|$`、`*|*`）时，成对删除两端符号。
    func handleDeleteBackward(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location > 0, let storage = textView.textStorage else {
            return false
        }

        let prevIndex = selection.location - 1
        let nsText = storage.string as NSString

        // 1. 数学公式附件还原为原始 LaTeX 源码，方便直接修改
        if prevIndex < storage.length {
            let attrs = storage.attributes(at: prevIndex, effectiveRange: nil)
            if let source = attrs[Self.markdownSourceKey] as? String,
               let kind = attrs[Self.markdownEntityKindKey] as? String,
               (kind == EditorEntityKind.inlineMath.rawValue || kind == EditorEntityKind.displayMath.rawValue)
            {
                let replaceRange = NSRange(location: prevIndex, length: 1)
                textView.insertText(source, replacementRange: replaceRange)
                // 把光标放在闭合 `$`/`$$` 之前，便于立即编辑公式内容
                let delimiterLen = (kind == EditorEntityKind.displayMath.rawValue) ? 2 : 1
                let caretPos = prevIndex + max(0, (source as NSString).length - delimiterLen)
                textView.setSelectedRange(NSRange(location: caretPos, length: 0))
                return true
            }
        }

        // 2. 空配对符号成对删除
        if selection.location < nsText.length {
            let left = nsText.substring(with: NSRange(location: prevIndex, length: 1))
            let right = nsText.substring(with: NSRange(location: selection.location, length: 1))
            if Self.autoPairs[left] == right {
                let pairRange = NSRange(location: prevIndex, length: 2)
                textView.insertText("", replacementRange: pairRange)
                return true
            }
        }

        return false
    }

    // MARK: - Smart Newline (List Continuation, Renumbering & Math Block)

    /// 处理回车键：
    /// - 在空列表项/引用行按回车：退出列表/引用；
    /// - 在非空无序/有序/任务列表或引用行按回车：自动续行并重排后续有序编号；
    /// - 在 `$$` 独占行按回车：展开为块级公式 `$$\n|\n$$`。
    func handleInsertNewline(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let nsText = textView.string as NSString
        guard selection.location <= nsText.length else { return false }

        let lineRange = nsText.lineRange(for: selection)
        let rawLine = nsText.substring(with: lineRange)
        let lineNoNL = stripTrailingNewline(rawLine)
        let cursorInLine = selection.location - lineRange.location

        // 1. 独占行的 `$$`（光标在行尾）→ 展开块级公式
        let trimmed = lineNoNL.trimmingCharacters(in: .whitespaces)
        if trimmed == "$$" && cursorInLine >= (lineNoNL as NSString).length {
            let indent = String(lineNoNL.prefix(while: { $0 == " " || $0 == "\t" }))
            // 仅当当前尚未处于未闭合 $$ 块内时自动补闭合 $$
            let prefix = nsText.substring(with: NSRange(location: 0, length: lineRange.location))
            let precedingFences = countStandaloneDoubleDollarLines(in: prefix)
            if precedingFences % 2 == 0 {
                let insertion = "\n\(indent)\n\(indent)$$"
                textView.insertText(insertion, replacementRange: selection)
                let caretPos = selection.location + 1 + (indent as NSString).length
                textView.setSelectedRange(NSRange(location: caretPos, length: 0))
                return true
            }
        }

        // 2. 匹配列表 / 引用前缀
        guard let parsed = parseListOrQuoteLine(lineNoNL) else { return false }

        // 光标若在前缀内部，走默认换行
        guard cursorInLine >= parsed.prefixLength else { return false }

        // 2a. 空项（仅有前缀，正文为空）→ 清除当前行前缀退出列表
        if parsed.body.trimmingCharacters(in: .whitespaces).isEmpty {
            let clearRange = NSRange(location: lineRange.location, length: (lineNoNL as NSString).length)
            textView.insertText("", replacementRange: clearRange)
            return true
        }

        // 2b. 非空项 → 插入换行 + 续行前缀
        let nextPrefix: String
        switch parsed.kind {
        case .unordered(let marker):
            nextPrefix = "\(parsed.indent)\(marker) "
        case .task:
            nextPrefix = "\(parsed.indent)- [ ] "
        case .quote(let level):
            nextPrefix = "\(parsed.indent)\(String(repeating: ">", count: level)) "
        case .ordered(let number):
            nextPrefix = "\(parsed.indent)\(number + 1). "
        }

        textView.insertText("\n\(nextPrefix)", replacementRange: selection)

        // 若是有序列表，自动重排紧随其后的同缩进连续有序列表编号
        if case .ordered(let number) = parsed.kind {
            let insertedCaret = selection.location + 1 + (nextPrefix as NSString).length
            renumberOrderedList(
                startingAfterLineContaining: insertedCaret,
                expectedIndent: parsed.indent,
                nextNumber: number + 2,
                in: textView
            )
            textView.setSelectedRange(NSRange(location: insertedCaret, length: 0))
        }
        return true
    }

    // MARK: - Smart Two-Stage Home (⌘←)

    /// 两段式行首跳转（参考 Ulysses `performMoveToBeginningOfLineWithProposedLocation:`）：
    /// 第一次跳到行首 Markdown 标记之后的正文起点；若已在正文起点或之前，则跳到第 0 列。
    func handleMoveToBeginningOfLine(extendingSelection: Bool, in textView: NSTextView) -> Bool {
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.location <= nsText.length else { return false }

        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        let lineNoNL = stripTrailingNewline(nsText.substring(with: lineRange))
        let contentOffset = blockPrefixUTF16Length(of: lineNoNL)

        guard contentOffset > 0 else { return false }

        let contentStart = lineRange.location + contentOffset
        let target: Int
        if selection.location > contentStart {
            target = contentStart
        } else if selection.location == contentStart {
            target = lineRange.location
        } else {
            target = lineRange.location
        }

        if extendingSelection {
            let anchor = NSMaxRange(selection)
            let newRange = NSRange(location: min(target, anchor), length: abs(anchor - target))
            textView.setSelectedRange(newRange)
        } else {
            textView.setSelectedRange(NSRange(location: target, length: 0))
        }
        return true
    }

    // MARK: - Paragraph Reordering (⌥⌘↑ / ⌥⌘↓)

    /// 将当前光标所在行（或选中行块）向上/向下移动一行并保持选区偏移。
    @discardableResult
    func moveParagraph(up: Bool, in textView: NSTextView) -> Bool {
        let nsText = textView.string as NSString
        guard nsText.length > 0 else { return false }

        let selection = textView.selectedRange()
        let currentRange = nsText.lineRange(for: selection)

        if up {
            guard currentRange.location > 0 else { return false }
            let prevRange = nsText.lineRange(for: NSRange(location: currentRange.location - 1, length: 0))
            let prevText = nsText.substring(with: prevRange)
            let currText = nsText.substring(with: currentRange)

            let currHasNL = currText.hasSuffix("\n")
            let prevNoNL = stripTrailingNewline(prevText)
            let currNoNL = stripTrailingNewline(currText)

            let combined = currNoNL + "\n" + prevNoNL + (currHasNL ? "\n" : "")
            let swapRange = NSRange(location: prevRange.location, length: prevRange.length + currentRange.length)

            let relativeStart = selection.location - currentRange.location
            textView.insertText(combined, replacementRange: swapRange)
            let newStart = prevRange.location + min(relativeStart, (currNoNL as NSString).length)
            let newLen = min(selection.length, max(0, (combined as NSString).length - (newStart - prevRange.location)))
            textView.setSelectedRange(NSRange(location: newStart, length: newLen))
            return true
        } else {
            let currentEnd = NSMaxRange(currentRange)
            guard currentEnd < nsText.length else { return false }
            let nextRange = nsText.lineRange(for: NSRange(location: currentEnd, length: 0))
            let currText = nsText.substring(with: currentRange)
            let nextText = nsText.substring(with: nextRange)

            let nextHasNL = nextText.hasSuffix("\n")
            let currNoNL = stripTrailingNewline(currText)
            let nextNoNL = stripTrailingNewline(nextText)

            let combined = nextNoNL + "\n" + currNoNL + (nextHasNL ? "\n" : "")
            let swapRange = NSRange(location: currentRange.location, length: currentRange.length + nextRange.length)

            let relativeStart = selection.location - currentRange.location
            textView.insertText(combined, replacementRange: swapRange)
            let nextLineLenWithNL = (nextNoNL as NSString).length + 1
            let newStart = currentRange.location + nextLineLenWithNL + min(relativeStart, (currNoNL as NSString).length)
            let newLen = min(selection.length, max(0, (combined as NSString).length - (newStart - currentRange.location)))
            textView.setSelectedRange(NSRange(location: newStart, length: newLen))
            return true
        }
    }

    // MARK: - Lightweight Cursor Context Analysis (Zero Full-Text Reconstruction)

    /// 直接基于 `NSTextStorage` 的 backing string 与高亮器缓存区间分析上下文，
    /// 彻底避免每次移动光标时执行 `reconstructMarkdown`。
    func analyzeCursorContext(
        in textView: NSTextView,
        fencedCodeRanges: [NSRange],
        mathBlockRanges: [NSRange]
    ) -> EditorCursorContext {
        guard let storage = textView.textStorage else { return EditorCursorContext() }
        let nsText = storage.string as NSString
        let range = clamp(textView.selectedRange(), to: nsText.length)

        let blockContext = classifyBlockContext(
            range: range,
            in: nsText,
            fencedCodeRanges: fencedCodeRanges,
            mathBlockRanges: mathBlockRanges
        )
        let activeEntity = detectEntity(at: range.location, in: textView)
        let wikiQuery = (range.length == 0)
            ? detectWikiLinkQuery(at: range.location, in: nsText, textView: textView)
            : nil

        return EditorCursorContext(
            blockContext: blockContext,
            selectedRange: range,
            hasSelection: range.length > 0,
            activeEntity: activeEntity,
            wikiLinkQuery: wikiQuery
        )
    }

    /// 检测给定字符位置是否存在可编辑的 Markdown 实体（数学公式附件/源码、图片附件/源码、链接）。
    func detectEntity(at location: Int, in textView: NSTextView) -> EditorEntityInfo? {
        guard let storage = textView.textStorage, storage.length > 0 else { return nil }
        let nsText = storage.string as NSString

        // 1. 检查光标所在位置或紧邻左侧的附件实体（图片 / LaTeX 公式）
        let probeIndices = [location, location - 1].filter { $0 >= 0 && $0 < storage.length }
        for idx in probeIndices {
            let attrs = storage.attributes(at: idx, effectiveRange: nil)
            if let source = attrs[Self.markdownSourceKey] as? String {
                let kindRaw = attrs[Self.markdownEntityKindKey] as? String
                let entityRange = NSRange(location: idx, length: 1)
                let frame = boundingFrameInWindow(for: entityRange, in: textView)

                if kindRaw == EditorEntityKind.displayMath.rawValue || source.hasPrefix("$$") {
                    let inner = stripMathDelimiters(source, isDisplay: true)
                    return EditorEntityInfo(
                        kind: .displayMath,
                        range: entityRange,
                        source: source,
                        primaryText: inner,
                        frameInWindow: frame
                    )
                }
                if kindRaw == EditorEntityKind.inlineMath.rawValue
                    || (source.hasPrefix("$") && source.hasSuffix("$"))
                {
                    let inner = stripMathDelimiters(source, isDisplay: false)
                    return EditorEntityInfo(
                        kind: .inlineMath,
                        range: entityRange,
                        source: source,
                        primaryText: inner,
                        frameInWindow: frame
                    )
                }
                if let parsedImage = parseImageMarkdown(source) {
                    return EditorEntityInfo(
                        kind: .image,
                        range: entityRange,
                        source: source,
                        primaryText: parsedImage.alt,
                        secondaryText: parsedImage.url,
                        frameInWindow: frame
                    )
                }
            }
        }

        // 2. 检查当前行内的源码级实体（链接 / 未渲染图片 / 未渲染数学公式）
        let clampedLoc = min(location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: clampedLoc, length: 0))
        let lineStr = nsText.substring(with: lineRange)
        let localOffset = clampedLoc - lineRange.location

        // 2a. 链接 [text](url) 或图片 ![alt](url)
        if let regex = Self.linkOrImageRegex {
            let matches = regex.matches(in: lineStr, range: NSRange(location: 0, length: (lineStr as NSString).length))
            for match in matches {
                if localOffset >= match.range.location && localOffset <= NSMaxRange(match.range) {
                    let absRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
                    let raw = (lineStr as NSString).substring(with: match.range)
                    let isImage = raw.hasPrefix("!")
                    let primary = (lineStr as NSString).substring(with: match.range(at: 1))
                    let secondary = (lineStr as NSString).substring(with: match.range(at: 2))
                    return EditorEntityInfo(
                        kind: isImage ? .image : .link,
                        range: absRange,
                        source: raw,
                        primaryText: primary,
                        secondaryText: secondary,
                        frameInWindow: boundingFrameInWindow(for: absRange, in: textView)
                    )
                }
            }
        }

        // 2b. 单行源码级 $$...$$ 或 $...$
        if let regex = Self.inlineOrSingleLineMathRegex {
            let matches = regex.matches(in: lineStr, range: NSRange(location: 0, length: (lineStr as NSString).length))
            for match in matches {
                if localOffset >= match.range.location && localOffset <= NSMaxRange(match.range) {
                    let absRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
                    let raw = (lineStr as NSString).substring(with: match.range)
                    let isDisplay = raw.hasPrefix("$$")
                    return EditorEntityInfo(
                        kind: isDisplay ? .displayMath : .inlineMath,
                        range: absRange,
                        source: raw,
                        primaryText: stripMathDelimiters(raw, isDisplay: isDisplay),
                        frameInWindow: boundingFrameInWindow(for: absRange, in: textView)
                    )
                }
            }
        }

        return nil
    }

    /// 计算字符区间在所属窗口坐标系下的矩形，用于定位浮动气泡。
    func boundingFrameInWindow(for range: NSRange, in textView: NSTextView) -> CGRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return nil }
        let safeRange = clamp(range, to: (textView.string as NSString).length)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: safeRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return textView.convert(rect, to: nil)
    }

    // MARK: - Private Classification Helpers

    private func classifyBlockContext(
        range: NSRange,
        in text: NSString,
        fencedCodeRanges: [NSRange],
        mathBlockRanges: [NSRange]
    ) -> EditorBlockContext {
        // 1. O(K) 命中缓存的围栏代码块与块级公式区间（K 通常很小）
        for codeRange in fencedCodeRanges {
            if range.location >= codeRange.location && range.location <= NSMaxRange(codeRange) {
                return .codeBlock
            }
        }
        for mathRange in mathBlockRanges {
            if range.location >= mathRange.location && range.location <= NSMaxRange(mathRange) {
                return .mathBlock
            }
        }

        // 2. 精确计算当前段落几何边界（1:1 对齐 Ulysses `_actionScope` 的 getParagraphStart:end:contentsEnd:forRange:）
        var paraStart = 0
        var paraEnd = 0
        var contentsEnd = 0
        let safeLoc = min(range.location, text.length)
        text.getParagraphStart(
            &paraStart,
            end: &paraEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: safeLoc, length: 0)
        )
        let paraRange = NSRange(location: paraStart, length: max(0, contentsEnd - paraStart))
        let lineNoNL = paraRange.length > 0 ? text.substring(with: paraRange) : ""
        let trimmed = lineNoNL.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))

        if trimmed.hasPrefix("$$") {
            return .mathBlock
        }

        // 3. 有选区：按 Ulysses Scope 4（跨多段）/ Scope 3（单整段）/ Scope 1（行内局部选区）判定
        if range.length > 0 {
            let selEnd = NSMaxRange(range)
            if selEnd > paraEnd {
                return .fullLines
            }
            if selEnd == paraEnd || (range.location <= paraStart && selEnd >= contentsEnd) {
                return .fullLine(
                    suggestedHeadingLevel: suggestedHeadingLevel(before: paraStart, in: text)
                )
            }
            return .inlineText
        }

        // 4. Scope 0：无选区且为空行（paraStart == contentsEnd 或仅含空白）
        if trimmed.isEmpty {
            return .empty(
                suggestedHeadingLevel: suggestedHeadingLevel(before: paraStart, in: text)
            )
        }

        // 5. 非空段落：计算正文内容起点 contentStart（跳过行首空白与 # / - / 1. / > 标记）
        let prefixLen = blockPrefixUTF16Length(of: lineNoNL)
        let leadingWSLen = (String(lineNoNL.prefix(while: { $0 == " " || $0 == "\t" })) as NSString).length
        let contentStart = paraStart + max(prefixLen, leadingWSLen)

        // 光标越过行首前缀进入正文句中或段尾 → Scope 1（行内模式，与 Ulysses 100% 一致）
        if range.location > contentStart {
            return .paragraphText
        }

        // 光标位于行首或行首前缀处 → Scope 2（块级转换 / 切换模式）
        if let level = Self.headingLevel(of: trimmed) {
            return .headingLine(level: level)
        }
        if trimmed.hasPrefix(">") {
            return .quoteLine
        }
        if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
            || trimmed.hasPrefix("* [ ]") || trimmed.hasPrefix("* [x]") || trimmed.hasPrefix("* [X]")
        {
            return .listLine(kind: .task)
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return .listLine(kind: .unordered)
        }
        if Self.isOrderedListPrefix(trimmed) {
            return .listLine(kind: .ordered)
        }

        return .paragraphStart(
            suggestedHeadingLevel: suggestedHeadingLevel(before: paraStart, in: text)
        )
    }

    private func detectWikiLinkQuery(
        at location: Int,
        in text: NSString,
        textView: NSTextView
    ) -> EditorWikiLinkQuery? {
        guard location >= 2 else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        let prefixLen = location - lineRange.location
        guard prefixLen >= 2 else { return nil }

        let prefix = text.substring(with: NSRange(location: lineRange.location, length: prefixLen))
        // 查找当前行光标前最后一个未闭合的 `[[`
        guard let openRange = prefix.range(of: "[[", options: .backwards) else { return nil }
        let afterOpen = String(prefix[openRange.upperBound...])
        // 若中间已出现 `]]` 或 `|` 或换行则不触发补全
        if afterOpen.contains("]]") || afterOpen.contains("\n") || afterOpen.contains("[") {
            return nil
        }

        let openUTF16Offset = (String(prefix[..<openRange.lowerBound]) as NSString).length
        let absStart = lineRange.location + openUTF16Offset
        let replaceRange = NSRange(location: absStart, length: location - absStart)
        let caretRect = boundingFrameInWindow(for: NSRange(location: location, length: 0), in: textView)
        return EditorWikiLinkQuery(
            replaceRange: replaceRange,
            query: afterOpen,
            caretFrameInWindow: caretRect
        )
    }

    /// 向上回溯最近的标题行，智能推荐下一级标题（钳制在 1...3，对齐 Ulysses `tagForOffsettingHeadingLevelAtSelectionBy: 1`）。
    private func suggestedHeadingLevel(before location: Int, in text: NSString) -> Int {
        var cursor = location
        var steps = 0
        while cursor > 0 && steps < 80 {
            steps += 1
            let prevRange = text.lineRange(for: NSRange(location: cursor - 1, length: 0))
            let prev = text.substring(with: prevRange)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r"))
            if let level = Self.headingLevel(of: prev) {
                switch level {
                case 1: return 2
                case 2: return 3
                default: return 3
                }
            }
            cursor = prevRange.location
        }
        return 1
    }

    // MARK: - List / Prefix Parsing Helpers

    private enum LinePrefixKind {
        case unordered(String)
        case ordered(Int)
        case task
        case quote(Int)
    }

    private struct ParsedLinePrefix {
        let indent: String
        let kind: LinePrefixKind
        let prefixLength: Int
        let body: String
    }

    private func parseListOrQuoteLine(_ line: String) -> ParsedLinePrefix? {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = String(line.dropFirst(indent.count))

        // 1. Task list: - [ ] / - [x] / - [X]
        if let m = rest.range(of: #"^[-*+]\s+\[[ xX]\]\s"#, options: .regularExpression) {
            let prefix = indent + String(rest[m])
            return ParsedLinePrefix(
                indent: indent,
                kind: .task,
                prefixLength: (prefix as NSString).length,
                body: String(rest[m.upperBound...])
            )
        }

        // 2. Unordered list: - / * / +
        if let m = rest.range(of: #"^([-*+])\s"#, options: .regularExpression) {
            let marker = String(rest.prefix(1))
            let prefix = indent + String(rest[m])
            return ParsedLinePrefix(
                indent: indent,
                kind: .unordered(marker),
                prefixLength: (prefix as NSString).length,
                body: String(rest[m.upperBound...])
            )
        }

        // 3. Ordered list: 1.
        if let m = rest.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
            let matched = String(rest[m])
            let digits = matched.prefix(while: { $0.isNumber })
            if let number = Int(digits) {
                let prefix = indent + matched
                return ParsedLinePrefix(
                    indent: indent,
                    kind: .ordered(number),
                    prefixLength: (prefix as NSString).length,
                    body: String(rest[m.upperBound...])
                )
            }
        }

        // 4. Blockquote: > / >>
        if let m = rest.range(of: #"^(>+)\s?"#, options: .regularExpression) {
            let matched = String(rest[m])
            let level = matched.filter { $0 == ">" }.count
            let prefix = indent + matched
            return ParsedLinePrefix(
                indent: indent,
                kind: .quote(max(1, level)),
                prefixLength: (prefix as NSString).length,
                body: String(rest[m.upperBound...])
            )
        }

        return nil
    }

    private func renumberOrderedList(
        startingAfterLineContaining location: Int,
        expectedIndent: String,
        nextNumber: Int,
        in textView: NSTextView
    ) {
        let nsText = textView.string as NSString
        guard location <= nsText.length else { return }

        let currentLineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        var scanPos = NSMaxRange(currentLineRange)
        var expectedNum = nextNumber
        var replacements: [(NSRange, String)] = []

        while scanPos < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: scanPos, length: 0))
            let line = stripTrailingNewline(nsText.substring(with: lineRange))
            guard let parsed = parseListOrQuoteLine(line),
                  parsed.indent == expectedIndent,
                  case .ordered(let existingNum) = parsed.kind
            else {
                break
            }

            if existingNum != expectedNum {
                let indentLen = (expectedIndent as NSString).length
                let oldNumLen = (String(existingNum) as NSString).length
                let numRange = NSRange(location: lineRange.location + indentLen, length: oldNumLen)
                replacements.append((numRange, "\(expectedNum)"))
            }
            expectedNum += 1
            scanPos = NSMaxRange(lineRange)
        }

        for (range, replacement) in replacements.reversed() {
            textView.insertText(replacement, replacementRange: range)
        }
    }

    private func blockPrefixUTF16Length(of line: String) -> Int {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = String(line.dropFirst(indent.count))

        let patterns = [
            #"^#{1,6}[ \t]+"#,
            #"^[-*+][ \t]+\[[ xX]\][ \t]+"#,
            #"^[-*+][ \t]+"#,
            #"^\d+\.[ \t]+"#,
            #"^>+[ \t]?"#,
        ]
        for pattern in patterns {
            if let match = rest.range(of: pattern, options: .regularExpression) {
                let fullPrefix = indent + String(rest[match])
                return (fullPrefix as NSString).length
            }
        }
        return (indent as NSString).length
    }

    private func stripTrailingNewline(_ s: String) -> String {
        if s.hasSuffix("\r\n") { return String(s.dropLast(2)) }
        if s.hasSuffix("\n") { return String(s.dropLast()) }
        return s
    }

    private func countStandaloneDoubleDollarLines(in text: String) -> Int {
        text.components(separatedBy: "\n").reduce(into: 0) { count, line in
            if line.trimmingCharacters(in: .whitespaces) == "$$" {
                count += 1
            }
        }
    }

    private func stripMathDelimiters(_ source: String, isDisplay: Bool) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDisplay, trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 {
            return String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !isDisplay, trimmed.hasPrefix("$"), trimmed.hasSuffix("$"), trimmed.count >= 2 {
            return String(trimmed.dropFirst(1).dropLast(1)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private func parseImageMarkdown(_ source: String) -> (alt: String, url: String)? {
        guard let regex = Self.imageOnlyRegex else { return nil }
        let ns = source as NSString
        guard let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2)))
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let loc = max(0, min(range.location, length))
        let len = max(0, min(range.length, length - loc))
        return NSRange(location: loc, length: len)
    }

    private static func headingLevel(of line: String) -> Int? {
        var count = 0
        for ch in line {
            if ch == "#" {
                count += 1
                if count > 6 { return nil }
            } else if ch == " " || ch == "\t" {
                return count >= 1 ? count : nil
            } else {
                return nil
            }
        }
        return nil
    }

    private static func isOrderedListPrefix(_ s: String) -> Bool {
        var idx = s.startIndex
        var sawDigit = false
        while idx < s.endIndex, s[idx].isNumber {
            sawDigit = true
            idx = s.index(after: idx)
        }
        guard sawDigit, idx < s.endIndex, s[idx] == "." else { return false }
        let afterDot = s.index(after: idx)
        return afterDot < s.endIndex && s[afterDot] == " "
    }

    // MARK: - Compiled Regexes

    private static let linkOrImageRegex = try? NSRegularExpression(
        pattern: #"!?\[([^\]]*)\]\(([^)]*)\)"#
    )

    private static let imageOnlyRegex = try? NSRegularExpression(
        pattern: #"^!\[([^\]]*)\]\(([^)]*)\)$"#
    )

    private static let inlineOrSingleLineMathRegex = try? NSRegularExpression(
        pattern: #"\$\$([^\n$]+?)\$\$|(?<!\$)\$(?!\$)(?!\s)([^\n$]+?)(?<!\s)\$(?!\$)"#
    )
}
