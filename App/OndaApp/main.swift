import AppKit

// Entry point dell'app. Come eseguibile SPM configuriamo manualmente
// NSApplication (l'app bundle vero e proprio, con Info.plist ed entitlements,
// arriva con la fase Xcode descritta in CLAUDE.md).
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.activate(ignoringOtherApps: true)
application.run()
