//
//  ScreenCaptureManager.swift
//  MultiOCR
//
//  Handles screen capture with crosshair selection
//

import Cocoa
import ScreenCaptureKit

class ScreenCaptureManager: NSObject, NSWindowDelegate {
    private var selectionWindow: SelectionOverlayWindow?
    private var completionHandler: ((NSImage?) -> Void)?
    
    func captureScreen(completion: @escaping (NSImage?) -> Void) {
        self.completionHandler = completion
        
        // Check for screen recording permission
        checkScreenRecordingPermission { [weak self] granted in
            if granted {
                self?.showSelectionOverlay()
            } else {
                self?.requestScreenRecordingPermission()
                completion(nil)
            }
        }
    }
    
    private func checkScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        if #available(macOS 12.3, *) {
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    let hasPermission = !content.displays.isEmpty
                    await MainActor.run {
                        completion(hasPermission)
                    }
                } catch {
                    // If we get an error, it might be permission denied
                    // But for development, let's try to proceed anyway
                    await MainActor.run {
                        // Try to proceed - if permission is really denied, capture will fail gracefully
                        completion(true)
                    }
                }
            }
        } else {
            // For older macOS versions, assume permission is granted
            completion(true)
        }
    }
    
    private func requestScreenRecordingPermission() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "MultiOCR needs permission to record your screen to capture areas for OCR. Please grant permission in System Preferences > Security & Privacy > Screen Recording."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    private func showSelectionOverlay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Activate the app to show windows
            NSApp.activate(ignoringOtherApps: true)
            
            // Get main screen
            guard let screen = NSScreen.main else {
                self.completionHandler?(nil)
                return
            }
            
            // Create selection overlay window
            self.selectionWindow = SelectionOverlayWindow(screen: screen) { [weak self] selectedRect in
                self?.captureRect(selectedRect, on: screen)
            }
            
            self.selectionWindow?.delegate = self
            self.selectionWindow?.makeKeyAndOrderFront(nil)
            // Force activation again to ensure we get focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func captureRect(_ rect: CGRect, on screen: NSScreen) {
        // Close overlay window immediately
        selectionWindow?.close()
        selectionWindow = nil
        
        // Small delay to allow window to close completely before capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Capture the selected area
            guard let windowID = CGWindowID(kCGNullWindowID) as CGWindowID?,
                  let image = CGWindowListCreateImage(
                    rect,
                    .optionOnScreenOnly,
                    windowID,
                    [.bestResolution, .boundsIgnoreFraming]
                  ) else {
                self.completionHandler?(nil)
                return
            }
            
            let nsImage = NSImage(cgImage: image, size: rect.size)
            self.completionHandler?(nsImage)
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == selectionWindow {
            selectionWindow = nil
        }
    }
}
