import Foundation
import Sparkle

/// Sparkle, reduced to what this app shows: a manual check in the context menu and an
/// "automatic updates" switch in the settings.
///
/// The feed URL and the public EdDSA key live in the bundle's `Info.plist`
/// (`SUFeedURL`, `SUPublicEDKey`), written by `scripts/build-app.sh`.
@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
    }

    /// False while a check is already running — the menu item is rebuilt on every
    /// right-click, so reading it there is enough and saves a KVO observer.
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// `CFBundleShortVersionString`, or nil outside an app bundle (`swift run`).
    static var displayedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
