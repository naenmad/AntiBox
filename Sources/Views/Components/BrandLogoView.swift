import SwiftUI
import AppKit

public enum BrandLogoKind: Sendable {
    case gemini
    case claude
    case chatgpt
    case claudeAndGpt
}

/// Native vector-sharp brand logo view for Gemini, Claude, and ChatGPT / GPT-OSS
public struct BrandLogoView: View {
    public let kind: BrandLogoKind
    public var size: CGFloat

    public init(_ kind: BrandLogoKind, size: CGFloat = 16) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        Group {
            switch kind {
            case .gemini:
                singleLogo(name: "gemini_logo", fallbackSystemIcon: "sparkles", fallbackColor: .cyan)
                    .frame(width: size, height: size)
            case .claude:
                singleLogo(name: "claude_logo", fallbackSystemIcon: "cpu", fallbackColor: .orange)
                    .frame(width: size, height: size)
            case .chatgpt:
                singleLogo(name: "chatgpt_logo", fallbackSystemIcon: "circle.grid.hex", fallbackColor: .teal)
                    .frame(width: size, height: size)
            case .claudeAndGpt:
                HStack(spacing: 3) {
                    singleLogo(name: "claude_logo", fallbackSystemIcon: "cpu", fallbackColor: .orange)
                        .frame(width: size, height: size)
                    singleLogo(name: "chatgpt_logo", fallbackSystemIcon: "circle.grid.hex", fallbackColor: .teal)
                        .frame(width: size, height: size)
                }
                .frame(height: size)
            }
        }
    }

    @ViewBuilder
    private func singleLogo(name: String, fallbackSystemIcon: String, fallbackColor: Color) -> some View {
        if let nsImage = Self.loadLogoImage(named: name, targetSize: size) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemIcon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundColor(fallbackColor)
        }
    }

    private static func loadLogoImage(named name: String, targetSize: CGFloat) -> NSImage? {
        var sourceImage: NSImage?

        // 1. Try Bundle.main (prefer SVG for crisp vector transparency, then PNG)
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") ?? Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            sourceImage = img
        }

        // 2. Try App bundle Contents/Resources/
        if sourceImage == nil {
            let appBundleSvg = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).svg")
            if FileManager.default.fileExists(atPath: appBundleSvg.path), let img = NSImage(contentsOf: appBundleSvg) {
                sourceImage = img
            } else {
                let appBundlePng = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).png")
                if FileManager.default.fileExists(atPath: appBundlePng.path), let img = NSImage(contentsOf: appBundlePng) {
                    sourceImage = img
                }
            }
        }

        // 3. Fallback to local project Assets path
        if sourceImage == nil {
            let localSvg = URL(fileURLWithPath: "Assets/\(name).svg")
            if FileManager.default.fileExists(atPath: localSvg.path), let img = NSImage(contentsOf: localSvg) {
                sourceImage = img
            } else {
                let localPng = URL(fileURLWithPath: "Assets/\(name).png")
                if FileManager.default.fileExists(atPath: localPng.path), let img = NSImage(contentsOf: localPng) {
                    sourceImage = img
                }
            }
        }

        guard let source = sourceImage else { return nil }

        // Create an exact resolution-independent NSImage matching targetSize in points
        let sizedImage = NSImage(size: NSSize(width: targetSize, height: targetSize), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        sizedImage.isTemplate = false
        return sizedImage
    }
}
