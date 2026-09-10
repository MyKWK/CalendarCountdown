import SwiftUI

extension View {
    /// Keeps an action focusable while suppressing SwiftUI's extra outer focus halo.
    ///
    /// Apply this to buttons and compact action menus. Editing controls such as
    /// text fields, pickers, and date pickers intentionally keep their native
    /// focus indication.
    func appActionFocusEffectDisabled() -> some View {
        focusEffectDisabled()
    }

    @ViewBuilder
    func appBorderlessMenuStyle() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton)
        #else
        self
        #endif
    }
}
