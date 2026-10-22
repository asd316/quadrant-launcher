import AppKit
import QuadrantCore
import enum QuadrantCore.Edge
import SwiftUI

/// Colors and metrics from the Figma light and dark screens.
struct Theme {
    let isDark: Bool

    init(_ scheme: ColorScheme) { isDark = scheme == .dark }

    private static func gray(_ value: Int, _ opacity: Double = 1) -> Color {
        Color(white: Double(value) / 255, opacity: opacity)
    }

    private func pick(_ light: Color, _ dark: Color) -> Color { isDark ? dark : light }

    var panelBackground: Color { pick(Self.gray(247, 0.94), Self.gray(28, 0.94)) }
    /// Fallback for static renders where the blur is unavailable: the tint composited on a typical backdrop.
    var panelSolid: Color { pick(Self.gray(244), Self.gray(30)) }
    var quadrantTint: Color { pick(Color.black.opacity(0.018), Color.white.opacity(0.018)) }
    var diagonal: Color { pick(Color.black.opacity(0.06), Color.white.opacity(0.06)) }
    var title: Color { pick(Self.gray(0x26), Self.gray(0xe6)) }
    var shelfBackground: Color { pick(Color.black.opacity(0.02), Color.white.opacity(0.03)) }
    var shelfText: Color { pick(Self.gray(0x60), Self.gray(0xa6)) }
    var branchText: Color { pick(Self.gray(0x4c), Self.gray(0xc3)) }
    var focusFill: Color { pick(Self.gray(0x3a), Self.gray(0xcb)) }
    var focusText: Color { pick(Self.gray(0xfa), Self.gray(0x23)) }
    var badgeFill: Color { pick(Color.white.opacity(0.12), Color.black.opacity(0.12)) }
    var starLabel: Color { pick(Self.gray(0x65), Self.gray(0x99)) }
    var hint: Color { pick(Self.gray(0x4c), Self.gray(0x99)) }
    var hover: Color { pick(Color.black.opacity(0.05), Color.white.opacity(0.08)) }
    var broken: Color { pick(Self.gray(0x9a), Self.gray(0x70)) }

    var stashFill: Color { pick(Self.gray(236, 0.48), Self.gray(60, 0.48)) }
    var stashBorder: Color { pick(Color.black.opacity(0.14), Self.gray(200, 0.19)) }
    var stashSlotFill: Color { pick(Color.black.opacity(0.03), Color.white.opacity(0.06)) }
    var stashText: Color { pick(Self.gray(0x26), Self.gray(0xdc)) }
    var stashDash: Color { pick(Color.black.opacity(0.12), Color.white.opacity(0.16)) }
    var stashShadow: Color { Color.black.opacity(isDark ? 0.18 : 0.05) }

    var lensFill: Color { pick(Self.gray(236, 0.78), Self.gray(44, 0.94)) }
    var lensBorder: Color { pick(Color.black.opacity(0.14), Self.gray(200, 0.19)) }
    var lensText: Color { pick(Self.gray(0x26), Self.gray(0xdc)) }
    var lensCount: Color { pick(Self.gray(0x5e), Self.gray(0xaf)) }
    var divider: Color { pick(Color.black.opacity(0.07), Color.white.opacity(0.07)) }
    var actionFill: Color { pick(Color.white.opacity(0.9), Self.gray(55, 0.9)) }
    var actionBorder: Color { pick(Color.black.opacity(0.08), Color.white.opacity(0.12)) }
    var folderIcon: Color { pick(Self.gray(0x80), Self.gray(0x9a)) }
    var lensShadowRadius: CGFloat { isDark ? 16 : 12 }
    var lensShadowY: CGFloat { isDark ? 3 : 2 }
    var lensShadow: Color { Color.black.opacity(isDark ? 0.18 : 0.05) }

    var accent: Color { Color.accentColor }

    static let titleFont = Font.system(size: 18, weight: .medium)
    static let rowFont = Font.system(size: 14, weight: .medium)
    static let smallFont = Font.system(size: 12)
}

private struct StaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering to an image: blur and AppKit overlays are unavailable, so solid fallbacks are used.
    var isStaticRender: Bool {
        get { self[StaticRenderKey.self] }
        set { self[StaticRenderKey.self] = newValue }
    }
}

extension View {
    /// Use solid fallbacks instead of the behind-window blur. For `ImageRenderer` output (UIPreview, tests).
    public func staticRendering() -> some View {
        environment(\.isStaticRender, true)
    }
}

/// Behind-window or within-window blur.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blending
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Blur plus tint for floating surfaces (stash, lens). Solid tint only in static renders.
struct Glass: View {
    @Environment(\.isStaticRender) private var isStatic
    var fill: Color
    var radius: CGFloat
    var behindWindow = false

    var body: some View {
        ZStack {
            if !isStatic {
                VisualEffectBackground(material: .hudWindow, blending: behindWindow ? .behindWindow : .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
            }
            RoundedRectangle(cornerRadius: radius).fill(fill)
        }
    }
}

func estimatedTextWidth(_ text: String, size: CGFloat) -> CGFloat {
    text.unicodeScalars.reduce(0) { $0 + ($1.value >= 0x2E80 ? size : size * 0.56) }
}

