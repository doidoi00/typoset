//
//  StatusBarController.swift
//  MultiOCR
//
//  Manages the menubar icon and menu
//

import Cocoa
import SwiftUI
import UserNotifications

class StatusBarController: NSObject, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var screenCaptureManager: ScreenCaptureManager
    private var ocrManager: OCRManager
    private var resultWindow: NSWindow?
    
    override init() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Initialize managers
        screenCaptureManager = ScreenCaptureManager()
        ocrManager = OCRManager.shared
        
        // Create menu
        menu = NSMenu()
        
        super.init()
        
        if let button = statusItem.button {
            // Set icon (using SF Symbol for now, will be replaced with custom icon)
            button.image = NSImage(systemSymbolName: "doc.text.viewfinder", accessibilityDescription: "MultiOCR")
            button.image?.isTemplate = true
        }
        
        setupMenu()
        statusItem.menu = menu
        
        // Request notification permission
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupMenu() {
        // Capture Screen Area
        let captureItem = NSMenuItem(
            title: "Capture Screen Area",
            action: #selector(startScreenCapture),
            keyEquivalent: ""
        )
        captureItem.target = self
        menu.addItem(captureItem)
        
        // Quick Capture submenu
        let quickCaptureItem = NSMenuItem(title: "Quick Capture", action: nil, keyEquivalent: "")
        let quickCaptureMenu = NSMenu()
        
        for engine in OCREngineType.allCases {
            let engineItem = NSMenuItem(
                title: "Capture with \(engine.displayName)",
                action: #selector(captureWithEngine(_:)),
                keyEquivalent: ""
            )
            engineItem.target = self
            engineItem.tag = engine.rawValue
            quickCaptureMenu.addItem(engineItem)
        }
        
        quickCaptureItem.submenu = quickCaptureMenu
        menu.addItem(quickCaptureItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recent Results
        let recentItem = NSMenuItem(title: "Recent Results", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        updateRecentResults()
        menu.addItem(recentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit MultiOCR",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }
    
    @objc func startScreenCapture() {
        let defaultEngine = SettingsManager.shared.defaultEngine
        captureAndProcess(with: defaultEngine)
    }
    
    @objc func captureWithEngine(_ sender: NSMenuItem) {
        guard let engine = OCREngineType(rawValue: sender.tag) else { return }
        captureAndProcess(with: engine)
    }
    
    private func captureAndProcess(with engine: OCREngineType) {
        screenCaptureManager.captureScreen { [weak self] image in
            guard let self = self, let image = image else { return }
            
            self.ocrManager.performOCR(on: image, using: engine) { result in
                switch result {
                case .success(let ocrResult):
                    self.handleOCRSuccess(ocrResult)
                case .failure(let error):
                    self.handleOCRError(error)
                }
            }
        }
    }
    
    private func handleOCRSuccess(_ result: OCRResult) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        
        // Update recent results
        updateRecentResults()
        
        // Show notification
        showNotification(title: "OCR Complete", message: "Text copied to clipboard")
        
        // Show result window
        DispatchQueue.main.async { [weak self] in
            self?.showResultWindow(for: result)
        }
    }
    
    private func showResultWindow(for result: OCRResult) {
        let resultView = ResultView(result: result)
        let hostingController = NSHostingController(rootView: resultView)
        
        if resultWindow == nil {
            resultWindow = NSWindow(contentViewController: hostingController)
            resultWindow?.title = "OCR Result"
            resultWindow?.styleMask = [.titled, .closable, .resizable]
            resultWindow?.setContentSize(NSSize(width: 500, height: 400))
            resultWindow?.center()
            resultWindow?.isReleasedWhenClosed = false
        } else {
            resultWindow?.contentViewController = hostingController
        }
        
        resultWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func handleOCRError(_ error: Error) {
        showNotification(title: "OCR Failed", message: error.localizedDescription)
    }
    
    private func updateRecentResults() {
        guard let recentItem = menu.item(withTitle: "Recent Results"),
              let submenu = recentItem.submenu else { return }
        
        submenu.removeAllItems()
        
        let recentResults = ocrManager.getRecentResults(limit: 5)
        
        if recentResults.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent results", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for (index, result) in recentResults.enumerated() {
                let preview = result.text.prefix(50).replacingOccurrences(of: "\n", with: " ")
                let title = "\(index + 1). \(preview)..."
                let item = NSMenuItem(
                    title: title,
                    action: #selector(copyRecentResult(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = result
                submenu.addItem(item)
            }
        }
    }
    
    @objc private func copyRecentResult(_ sender: NSMenuItem) {
        guard let result = sender.representedObject as? OCRResult else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        
        showNotification(title: "Copied", message: "Text copied to clipboard")
    }
    
    @objc private func openSettings() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showSettings()
        }
    }
    
    func showQuickCaptureMenu() {
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }
    
    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
