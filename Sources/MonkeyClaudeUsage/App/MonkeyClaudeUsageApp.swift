import MonkeyClaudeUsageCore
import SwiftUI

@main
struct MonkeyClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // The whole UI hangs off the status item; this scene only keeps SwiftUI happy.
        MenuBarExtra("", isInserted: .constant(false)) { EmptyView() }
    }
}
