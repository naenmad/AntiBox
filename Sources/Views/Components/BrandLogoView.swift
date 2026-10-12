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
            case .claude:
                singleLogo(name: "claude_logo", fallbackSystemIcon: "cpu", fallbackColor: .orange)
            case .chatgpt:
                singleLogo(name: "chatgpt_logo", fallbackSystemIcon: "circle.grid.hex", fallbackColor: .teal)
            case .claudeAndGpt:
                HStack(spacing: -size * 0.22) {
                    singleLogo(name: "claude_logo", fallbackSystemIcon: "cpu", fallbackColor: .orange)
                    singleLogo(name: "chatgpt_logo", fallbackSystemIcon: "circle.grid.hex", fallbackColor: .teal)
                }
            }
        }
    }

    @ViewBuilder
    private func singleLogo(name: String, fallbackSystemIcon: String, fallbackColor: Color) -> some View {
        if let nsImage = Self.loadLogoImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
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

    private static func loadLogoImage(named name: String) -> NSImage? {
        // 1. Try Bundle.main
        if let url = Bundle.main.url(forResource: name, withExtension: "png") ?? Bundle.main.url(forResource: name, withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // 2. Try App bundle Contents/Resources/
        let appBundlePng = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).png")
        if FileManager.default.fileExists(atPath: appBundlePng.path), let img = NSImage(contentsOf: appBundlePng) {
            return img
        }
        let appBundleSvg = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).svg")
        if FileManager.default.fileExists(atPath: appBundleSvg.path), let img = NSImage(contentsOf: appBundleSvg) {
            return img
        }
        // 3. Fallback to local project Assets path
        let localPng = URL(fileURLWithPath: "Assets/\(name).png")
        if FileManager.default.fileExists(atPath: localPng.path), let img = NSImage(contentsOf: localPng) {
            return img
        }
        let localSvg = URL(fileURLWithPath: "Assets/\(name).svg")
        if FileManager.default.fileExists(atPath: localSvg.path), let img = NSImage(contentsOf: localSvg) {
            return img
        }
        return nil
    }
}
