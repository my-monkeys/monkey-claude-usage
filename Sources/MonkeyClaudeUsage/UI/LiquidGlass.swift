import SwiftUI

/// Liquid Glass where the system has it, a plain material where it does not.
///
/// The app still runs on macOS 14, so every Tahoe API is reached behind `#available`
/// rather than by raising the deployment target — a menu bar utility is exactly the kind
/// of thing people keep on an older machine.
extension View {
    /// Glass surface for a panel: the popover body, a settings card.
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    /// Glass for a small interactive chip — a tab, a toggle.
    func glassChip(cornerRadius: CGFloat = 7, isProminent: Bool = false) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius, isProminent: isProminent))
    }
}

private struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

private struct GlassChip: ViewModifier {
    let cornerRadius: CGFloat
    let isProminent: Bool

    func body(content: Content) -> some View {
        // The fill goes on in every case, glass only on top of it. Liquid Glass samples
        // the window behind it, and in contexts where there is nothing to sample the
        // effect renders as nothing at all — a chip that vanishes is worse than a chip
        // that is merely opaque.
        let filled = content.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isProminent ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.08))
        )

        if #available(macOS 26, *) {
            // `.interactive()` is what makes the chip answer the pointer the way system
            // controls do on Tahoe; without it a custom surface feels inert beside them.
            filled.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            filled
        }
    }
}

/// Groups nearby glass surfaces so they sample one background and blend into each other
/// instead of each carrying its own edge.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
