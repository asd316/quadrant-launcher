import AppKit

// Throwaway spike (Architecture › Validation). Not part of the product.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let spikeController = SpikeController()
application.delegate = spikeController
application.run()
