import AppKit

class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            ScreenCaptureManager.shared.stopCapture()
        } else {
            super.keyDown(with: event)
        }
    }
}
