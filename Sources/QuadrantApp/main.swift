import AppKit

// Accessory app: no Dock icon, lives in the menu bar.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
