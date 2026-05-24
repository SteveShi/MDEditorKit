//
//  EditorTheme.swift
//  MDEditor
//
//  描述 MDEditorView 在所见即所得编辑态下的色彩方案。
//  与 MarkdownView 的预览主题（`MarkdownTheme`）相互独立：
//  - `MarkdownTheme` 控制只读 Markdown 预览的样式；
//  - `EditorTheme` 控制 TextKit 编辑器内部的字符着色、代码块底色、光标色等。
//

import AppKit
import CoreGraphics

/// 主题中使用的颜色描述。
/// 以 RGBA 浮点形式存储以保证 `Sendable` 与 `Equatable`，
/// 在运行时再按需转成 `NSColor`。
public struct EditorThemeColor: Sendable, Equatable, Hashable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(white: CGFloat, alpha: CGFloat = 1) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    /// 同色调透明度变体。
    public func opacity(_ value: CGFloat) -> EditorThemeColor {
        EditorThemeColor(red: red, green: green, blue: blue, alpha: alpha * value)
    }

    public var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// 编辑器主题。每一项含义参见各属性注释。
public struct EditorTheme: Sendable, Equatable, Hashable {
    /// 编辑器画布背景。MDEditor 内部的 `NSTextView` 始终绘制透明背景，
    /// 该字段供宿主应用读取以保证画布层与字符层视觉一致。
    public var background: EditorThemeColor
    /// 正文文本色。
    public var foreground: EditorThemeColor
    /// 标题（H1-H6）文本色。
    public var heading: EditorThemeColor
    /// Markdown 标记符号（# > * ` 等）的淡化色。
    public var syntaxMarker: EditorThemeColor
    /// 加粗/斜体等强调正文的着色（通常与 `foreground` 相同，可在彩色主题中区分）。
    public var emphasis: EditorThemeColor
    /// 行内代码文本色。
    public var inlineCode: EditorThemeColor
    /// 行内代码背景色。
    public var inlineCodeBackground: EditorThemeColor
    /// 围栏代码块背景色。
    public var codeBlockBackground: EditorThemeColor
    /// 引用块正文色。
    public var blockquote: EditorThemeColor
    /// 链接、任务列表勾选框、数学公式高亮色。
    public var link: EditorThemeColor
    /// 光标（插入点）颜色。
    public var insertionPoint: EditorThemeColor

    public init(
        background: EditorThemeColor,
        foreground: EditorThemeColor,
        heading: EditorThemeColor,
        syntaxMarker: EditorThemeColor,
        emphasis: EditorThemeColor,
        inlineCode: EditorThemeColor,
        inlineCodeBackground: EditorThemeColor,
        codeBlockBackground: EditorThemeColor,
        blockquote: EditorThemeColor,
        link: EditorThemeColor,
        insertionPoint: EditorThemeColor
    ) {
        self.background = background
        self.foreground = foreground
        self.heading = heading
        self.syntaxMarker = syntaxMarker
        self.emphasis = emphasis
        self.inlineCode = inlineCode
        self.inlineCodeBackground = inlineCodeBackground
        self.codeBlockBackground = codeBlockBackground
        self.blockquote = blockquote
        self.link = link
        self.insertionPoint = insertionPoint
    }

    /// 默认浅色主题：保持 MDEditor 1.6 时代的视觉。
    public static let `default` = EditorTheme(
        background: EditorThemeColor(white: 1.00),
        foreground: EditorThemeColor(white: 0.15),
        heading: EditorThemeColor(white: 0.00),
        syntaxMarker: EditorThemeColor(white: 0.50, alpha: 0.60),
        emphasis: EditorThemeColor(white: 0.15),
        inlineCode: EditorThemeColor(red: 0.80, green: 0.20, blue: 0.20),
        inlineCodeBackground: EditorThemeColor(white: 0.95),
        codeBlockBackground: EditorThemeColor(white: 0.95),
        blockquote: EditorThemeColor(white: 0.40),
        link: EditorThemeColor(red: 0.00, green: 0.48, blue: 1.00),
        insertionPoint: EditorThemeColor(white: 0.00)
    )

    /// 默认深色主题：浅色主题的明暗反向版本。
    public static let defaultDark = EditorTheme(
        background: EditorThemeColor(white: 0.10),
        foreground: EditorThemeColor(white: 0.88),
        heading: EditorThemeColor(white: 1.00),
        syntaxMarker: EditorThemeColor(white: 0.55, alpha: 0.65),
        emphasis: EditorThemeColor(white: 0.92),
        inlineCode: EditorThemeColor(red: 1.00, green: 0.60, blue: 0.60),
        inlineCodeBackground: EditorThemeColor(white: 0.18),
        codeBlockBackground: EditorThemeColor(white: 0.18),
        blockquote: EditorThemeColor(white: 0.60),
        link: EditorThemeColor(red: 0.40, green: 0.70, blue: 1.00),
        insertionPoint: EditorThemeColor(white: 1.00)
    )
}
