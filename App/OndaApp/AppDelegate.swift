import AppKit
import OndaShared

/// Delegate dell'applicazione: crea la finestra principale e dichiara l'attivita'
/// critica per evitare App Nap durante le sessioni di cattura/streaming.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Evita App Nap / throttling mentre l'app e' attiva (vedi CLAUDE.md).
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Cattura e rendering video in corso"
        )

        let controller = MainWindowController()
        controller.showWindow(nil)
        mainWindowController = controller

        OndaLog.app.info("Onda avviata")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
    }
}
