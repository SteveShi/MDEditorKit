//
//  EditorConfiguration.swift
//  MDEditor
//
//  编辑器配置选项
//

import AppKit
import SwiftUI

/// Markdown 标准
public enum MarkdownStandard: String, CaseIterable, Sendable, Identifiable {
    case markdownXL = "Markdown XL"
    case standard = "Standard"
    public var id: String { rawValue }
    public static let allCases: [MarkdownStandard] = [.markdownXL, .standard]
}

/// 编辑器配置
public struct EditorConfiguration: Sendable, Equatable, Hashable {
    /// 字体名称
    public var fontName: String
    /// 行高倍数
    public var lineHeightMultiple: CGFloat
    /// 页面宽度
    public var contentWidth: CGFloat
    /// 段落间距
    public var paragraphSpacing: CGFloat
    /// 首行缩进
    public var firstLineIndent: CGFloat

    /// 打字机模式
    public var typewriterMode: Bool
    /// Markdown 标准
    public var markdownStandard: MarkdownStandard

    /// 编辑器主题（字符着色、代码块底色、光标色等）
    public var theme: EditorTheme

    /// 水平边距
    public var horizontalPadding: CGFloat = 40
    /// 垂直边距
    public var verticalPadding: CGFloat = 20

    /// 图片提供者回调 (文件名) -> NSImage?
    public var imageProvider: (@Sendable (String) -> NSImage?)?

    /// 图片落盘回调：(NSImage) -> markdown 引用使用的 URL/相对路径字符串。
    /// 在 `MDEditorProxy.insertImage(_:altText:)` / 粘贴 / 拖拽时调用，
    /// 由宿主决定文件命名、存储位置；返回 nil 表示宿主放弃保存，编辑器不插入任何文本。
    public var imageSaver: (@Sendable (NSImage) -> String?)?

    /// 字号
    public var fontSize: CGFloat = 17.0

    /// 布局填充
    public var nsFont: NSFont {
        if fontName != "System", let font = NSFont(name: fontName, size: fontSize) {
            return font
        }
        // 默认使用苹方
        if let pingFang = NSFont(name: "PingFang SC", size: fontSize) {
            return pingFang
        }
        return .systemFont(ofSize: fontSize)
    }

    /// 默认配置
    public static let `default` = EditorConfiguration(
        fontName: "PingFang SC",
        lineHeightMultiple: 1.7,
        contentWidth: 750.0,
        paragraphSpacing: 18.0,
        firstLineIndent: 0.0,
        typewriterMode: false,
        markdownStandard: .markdownXL,
        theme: .default
    )

    public init(
        fontName: String = "PingFang SC",
        lineHeightMultiple: CGFloat = 1.7,
        contentWidth: CGFloat = 750.0,
        paragraphSpacing: CGFloat = 18.0,
        firstLineIndent: CGFloat = 0.0,
        typewriterMode: Bool = false,
        markdownStandard: MarkdownStandard = .markdownXL,
        theme: EditorTheme = .default,
        imageProvider: (@Sendable (String) -> NSImage?)? = nil,
        imageSaver: (@Sendable (NSImage) -> String?)? = nil
    ) {
        self.fontName = fontName
        self.lineHeightMultiple = lineHeightMultiple
        self.contentWidth = contentWidth
        self.paragraphSpacing = paragraphSpacing
        self.firstLineIndent = firstLineIndent
        self.typewriterMode = typewriterMode
        self.markdownStandard = markdownStandard
        self.theme = theme
        self.imageProvider = imageProvider
        self.imageSaver = imageSaver
    }

    // MARK: - Equatable & Hashable

    public static func == (lhs: EditorConfiguration, rhs: EditorConfiguration) -> Bool {
        lhs.fontName == rhs.fontName && lhs.lineHeightMultiple == rhs.lineHeightMultiple
            && lhs.contentWidth == rhs.contentWidth && lhs.paragraphSpacing == rhs.paragraphSpacing
            && lhs.firstLineIndent == rhs.firstLineIndent
            && lhs.typewriterMode == rhs.typewriterMode
            && lhs.markdownStandard == rhs.markdownStandard
            && lhs.theme == rhs.theme
            && lhs.horizontalPadding == rhs.horizontalPadding
            && lhs.verticalPadding == rhs.verticalPadding && lhs.fontSize == rhs.fontSize
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fontName)
        hasher.combine(lineHeightMultiple)
        hasher.combine(contentWidth)
        hasher.combine(paragraphSpacing)
        hasher.combine(firstLineIndent)
        hasher.combine(typewriterMode)
        hasher.combine(markdownStandard)
        hasher.combine(theme)
        hasher.combine(horizontalPadding)
        hasher.combine(verticalPadding)
        hasher.combine(fontSize)
    }
}
