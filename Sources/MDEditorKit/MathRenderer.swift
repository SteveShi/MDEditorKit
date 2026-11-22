//
//  MathRenderer.swift
//  MDEditorKit
//
//  基于 SwiftMath 的离线原生矢量 LaTeX 渲染器（带内存缓存与精确基线度量）。
//

import AppKit
import Foundation
import SwiftMath

/// 渲染后的 LaTeX 数学公式图像与基线排版信息。
public struct RenderedMath {
    public let image: NSImage
    public let ascent: CGFloat
    public let descent: CGFloat

    public init(image: NSImage, ascent: CGFloat, descent: CGFloat) {
        self.image = image
        self.ascent = ascent
        self.descent = descent
    }
}

private final class CachedMathBox: NSObject {
    let rendered: RenderedMath
    init(_ rendered: RenderedMath) {
        self.rendered = rendered
    }
}

/// 线程安全的 LaTeX 离线渲染与缓存服务。
/// 复用 SwiftMath 的 CoreGraphics 矢量绘制能力，避免在编辑器中嵌入多实例 WKWebView。
@MainActor
public final class MathRenderer {
    public static let shared = MathRenderer()

    private let cache: NSCache<NSString, CachedMathBox> = {
        let c = NSCache<NSString, CachedMathBox>()
        c.countLimit = 256
        return c
    }()

    private init() {}

    /// 渲染 LaTeX 表达式为矢量 `NSImage` 及基线偏移信息。
    /// 语法错误或空表达式返回 `nil`，调用方应优雅回退为源码高亮显示。
    public func render(
        latex: String,
        fontSize: CGFloat,
        textColor: NSColor,
        isDisplay: Bool
    ) -> RenderedMath? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let srgbColor = textColor.usingColorSpace(.sRGB) ?? textColor
        let r = Int((srgbColor.redComponent * 255).rounded())
        let g = Int((srgbColor.greenComponent * 255).rounded())
        let b = Int((srgbColor.blueComponent * 255).rounded())
        let a = Int((srgbColor.alphaComponent * 255).rounded())
        let scaledSize = isDisplay ? max(14, fontSize * 1.15) : max(12, fontSize * 1.02)

        let cacheKey =
            "\(isDisplay ? "D" : "I")|\(Int((scaledSize * 10).rounded()))|\(r),\(g),\(b),\(a)|\(trimmed)"
            as NSString
        if let hit = cache.object(forKey: cacheKey) {
            return hit.rendered
        }

        var mathImage = MathImage(
            latex: trimmed,
            fontSize: scaledSize,
            textColor: srgbColor,
            labelMode: isDisplay ? .display : .text,
            textAlignment: isDisplay ? .center : .left
        )
        mathImage.font = .latinModernFont
        mathImage.contentInsets = isDisplay
            ? MTEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            : MTEdgeInsets(top: 1, left: 2, bottom: 1, right: 2)

        let (error, image, layoutInfo) = mathImage.asImage()
        guard error == nil, let nsImage = image, nsImage.size.width > 0, nsImage.size.height > 0 else {
            return nil
        }

        let ascent = layoutInfo?.ascent ?? (nsImage.size.height * 0.75)
        let descent = layoutInfo?.descent ?? (nsImage.size.height * 0.25)
        let rendered = RenderedMath(image: nsImage, ascent: ascent, descent: descent)
        cache.setObject(CachedMathBox(rendered), forKey: cacheKey)
        return rendered
    }

    public func clearCache() {
        cache.removeAllObjects()
    }
}
