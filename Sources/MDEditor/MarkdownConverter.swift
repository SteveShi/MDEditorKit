//
//  MarkdownConverter.swift
//  MDEditor
//
//  Markdown 辅助工具类
//

import Foundation
import MarkdownParser

public struct MarkdownDocumentHeader: Sendable, Hashable {
    public let level: Int
    public let title: String
    public let lineIndex: Int

    public init(level: Int, title: String, lineIndex: Int) {
        self.level = level
        self.title = title
        self.lineIndex = lineIndex
    }
}

public struct MarkdownDocumentStatistics: Sendable, Hashable {
    public let characters: Int
    public let words: Int
    public let readingTime: Int

    public init(characters: Int, words: Int, readingTime: Int) {
        self.characters = characters
        self.words = words
        self.readingTime = readingTime
    }
}

/// Markdown 解析和转换工具
public struct MarkdownConverter {

    // MARK: - Markdown → HTML

    /// 将 Markdown 文本转换为 HTML
    public static func toHTML(_ markdown: String, imageResolver: (@Sendable (String) -> String)? = nil)
        -> String
    {
        let parser = MarkdownParser()
        let result = parser.parse(markdown)
        var html = ""
        for block in result.document {
            html += visitBlock(block, imageResolver: imageResolver)
        }
        return html
    }

    public static func headers(from markdown: String) -> [MarkdownDocumentHeader] {
        let parser = MarkdownParser()
        let result = parser.parse(markdown)
        let ranges = parser.parseBlockRange(markdown)
        
        var headers: [MarkdownDocumentHeader] = []
        
        for (index, block) in result.document.enumerated() {
            guard index < ranges.count else { break }
            if case let .heading(level, content) = block {
                let range = ranges[index]
                let lineIndex = calculateLineIndex(for: range.startIndex, in: markdown)
                headers.append(
                    MarkdownDocumentHeader(
                        level: level,
                        title: plainText(from: content),
                        lineIndex: lineIndex
                    )
                )
            }
        }
        return headers
    }

    public static func statistics(from markdown: String, readingWordsPerMinute: Int = 300)
        -> MarkdownDocumentStatistics
    {
        let plain = plainText(from: markdown)
        let wordCount = plain.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        let wordsPerMinute = max(1, readingWordsPerMinute)
        let readingTime = max(1, Int(ceil(Double(wordCount) / Double(wordsPerMinute))))
        return MarkdownDocumentStatistics(
            characters: markdown.count,
            words: wordCount,
            readingTime: readingTime
        )
    }

    public static func plainText(from markdown: String) -> String {
        let parser = MarkdownParser()
        let result = parser.parse(markdown)
        var text = ""
        for block in result.document {
            text += plainText(from: block)
        }
        return text
    }

    // MARK: - Private Helpers

    private static func calculateLineIndex(for index: String.Index, in text: String) -> Int {
        var count = 0
        var current = text.startIndex
        while current < index && current < text.endIndex {
            if text[current] == "\n" {
                count += 1
            }
            current = text.index(after: current)
        }
        return count
    }

    private static func visitBlock(_ block: MarkdownBlockNode, imageResolver: (@Sendable (String) -> String)? = nil) -> String {
        switch block {
        case let .blockquote(children):
            let body = children.map { visitBlock($0, imageResolver: imageResolver) }.joined()
            return "<blockquote>\n\(body)</blockquote>\n"
        case let .bulletedList(_, items):
            let body = items.map { item in
                let content = item.children.map { visitBlock($0, imageResolver: imageResolver) }.joined()
                return "<li>\(content)</li>\n"
            }.joined()
            return "<ul>\n\(body)</ul>\n"
        case let .numberedList(_, start, items):
            let startAttr = start != 1 ? " start=\"\(start)\"" : ""
            let body = items.map { item in
                let content = item.children.map { visitBlock($0, imageResolver: imageResolver) }.joined()
                return "<li>\(content)</li>\n"
            }.joined()
            return "<ol\(startAttr)>\n\(body)</ol>\n"
        case let .taskList(_, items):
            let body = items.map { item in
                let checked = item.isCompleted ? " checked" : ""
                let content = item.children.map { visitBlock($0, imageResolver: imageResolver) }.joined()
                return "<li><input type=\"checkbox\" disabled\(checked)> \(content)</li>\n"
            }.joined()
            return "<ul class=\"task-list\">\n\(body)</ul>\n"
        case let .codeBlock(fenceInfo, content):
            let langClass = fenceInfo.map { " class=\"language-\($0.htmlAttributeEscaped())\"" } ?? ""
            return "<pre><code\(langClass)>\(content.htmlEscaped())</code></pre>\n"
        case let .paragraph(content):
            let body = content.map { visitInline($0, imageResolver: imageResolver) }.joined()
            return "<p>\(body)</p>\n"
        case let .heading(level, content):
            let body = content.map { visitInline($0, imageResolver: imageResolver) }.joined()
            return "<h\(level)>\(body)</h\(level)>\n"
        case let .table(columnAlignments, rows):
            var html = "<table>\n"
            if let firstRow = rows.first {
                html += "<thead>\n<tr>\n"
                for (i, cell) in firstRow.cells.enumerated() {
                    let align = i < columnAlignments.count ? alignmentAttr(columnAlignments[i]) : ""
                    let content = cell.content.map { visitInline($0, imageResolver: imageResolver) }.joined()
                    html += "<th\(align)>\(content)</th>\n"
                }
                html += "</tr>\n</thead>\n"
            }
            if rows.count > 1 {
                html += "<tbody>\n"
                for row in rows.dropFirst() {
                    html += "<tr>\n"
                    for (i, cell) in row.cells.enumerated() {
                        let align = i < columnAlignments.count ? alignmentAttr(columnAlignments[i]) : ""
                        let content = cell.content.map { visitInline($0, imageResolver: imageResolver) }.joined()
                        html += "<td\(align)>\(content)</td>\n"
                    }
                    html += "</tr>\n"
                }
                html += "</tbody>\n"
            }
            html += "</table>\n"
            return html
        case .thematicBreak:
            return "<hr />\n"
        }
    }

    private static func alignmentAttr(_ alignment: RawTableColumnAlignment) -> String {
        switch alignment {
        case .left: return " align=\"left\""
        case .center: return " align=\"center\""
        case .right: return " align=\"right\""
        case .none: return ""
        }
    }

    private static func visitInline(_ inline: MarkdownInlineNode, imageResolver: (@Sendable (String) -> String)? = nil) -> String {
        switch inline {
        case let .text(text):
            return text.htmlEscaped()
        case .softBreak:
            return " "
        case .lineBreak:
            return "<br />\n"
        case let .code(code):
            return "<code>\(code.htmlEscaped())</code>"
        case let .html(html):
            return html
        case let .emphasis(children):
            let body = children.map { visitInline($0, imageResolver: imageResolver) }.joined()
            return "<em>\(body)</em>"
        case let .strong(children):
            let body = children.map { visitInline($0, imageResolver: imageResolver) }.joined()
            return "<strong>\(body)</strong>"
        case let .strikethrough(children):
            let body = children.map { visitInline($0, imageResolver: imageResolver) }.joined()
            return "<del>\(body)</del>"
        case let .link(destination, children):
            let body = children.map { visitInline($0, imageResolver: imageResolver) }.joined()
            return "<a href=\"\(destination.htmlAttributeEscaped())\">\(body)</a>"
        case let .image(source, children):
            let resolved = imageResolver?(source) ?? source
            let alt = plainText(from: children)
            return "<img src=\"\(resolved.htmlAttributeEscaped())\" alt=\"\(alt.htmlAttributeEscaped())\" />"
        case let .math(content, _):
            return "<span class=\"math\">\(content.htmlEscaped())</span>"
        }
    }

    private static func plainText(from block: MarkdownBlockNode) -> String {
        switch block {
        case let .blockquote(children):
            return children.map { plainText(from: $0) }.joined(separator: " ")
        case let .bulletedList(_, items):
            return items.map { item in item.children.map { plainText(from: $0) }.joined(separator: " ") }.joined(separator: "\n")
        case let .numberedList(_, _, items):
            return items.map { item in item.children.map { plainText(from: $0) }.joined(separator: " ") }.joined(separator: "\n")
        case let .taskList(_, items):
            return items.map { item in item.children.map { plainText(from: $0) }.joined(separator: " ") }.joined(separator: "\n")
        case let .codeBlock(_, content):
            return content
        case let .paragraph(content):
            return plainText(from: content)
        case let .heading(_, content):
            return plainText(from: content)
        case let .table(_, rows):
            return rows.map { row in row.cells.map { plainText(from: $0.content) }.joined(separator: " | ") }.joined(separator: "\n")
        case .thematicBreak:
            return ""
        }
    }

    private static func plainText(from inlines: [MarkdownInlineNode]) -> String {
        return inlines.map { plainText(from: $0) }.joined()
    }

    private static func plainText(from inline: MarkdownInlineNode) -> String {
        switch inline {
        case let .text(text): return text
        case .softBreak: return " "
        case .lineBreak: return "\n"
        case let .code(code): return code
        case let .html(html): return html
        case let .emphasis(children): return plainText(from: children)
        case let .strong(children): return plainText(from: children)
        case let .strikethrough(children): return plainText(from: children)
        case let .link(_, children): return plainText(from: children)
        case let .image(_, children): return plainText(from: children)
        case let .math(content, _): return content
        }
    }
    
    public static func isValid(_ markdown: String) -> Bool {
        return true
    }
}

private extension String {
    func htmlEscaped() -> String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    func htmlAttributeEscaped() -> String {
        htmlEscaped()
    }
}
