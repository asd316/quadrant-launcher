import AppKit

// Throwaway spike. Not part of the product.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let spikeController = SpikeController()
application.delegate = spikeController
application.run()
