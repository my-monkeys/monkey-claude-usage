import SwiftUI

/// Liquid Glass where the system has it, a plain material where it does not.
///
/// Two separate conditions, and both are needed. `#available` is a *runtime* check, so it
/// still requires the symbol to exist when compiling — building against the macOS 15 SDK
/// fails on `glassEffect` alone. `#if compiler(>=6.2)` stands in for "built with Xcode 26
/// or later", which is the toolchain that carries the API; without it the project would
/// only build on the newest Xcode, which is a lot to ask of a contributor.
///
/// The deployment target stays at macOS 14 either way — a menu bar utility is exactly the
/// kind of thing people keep running on an older machine.
extension View {
    /// Glass for a small interactive chip — a tab, a toggle.
    func glassChip(cornerRadius: CGFloat = 7, isProminent: Bool = false) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius, isProminent: isProminent))
    }
}

private struct GlassChip: ViewModifier {
    let cornerRadius: CGFloat
    let isProminent: Bool

    func body(content: Content) -> some View {
        // The fill goes on in every case, glass only over it. Liquid Glass samples the
        // window behind it, and where there is nothing to sample the effect renders as
        // nothing at all — a chip that vanishes is worse than one that is merely opaque.
        let filled = content.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isProminent ? Theme.accent.opacity(0.20) : Color.primary.opacity(0.08))
        )

        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            // `.interactive()` is what makes the chip answer the pointer the way system
            // controls do on Tahoe; without it a custom surface feels inert beside them.
            filled.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            filled
        }
        #else
        filled
        #endif
    }
}
