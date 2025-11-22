//
//  AppDelegate.swift
//  MultiOCR
//
//  Handles app lifecycle and global keyboard shortcuts
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusBarController: StatusBarController?
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize status bar controller
        statusBarController = StatusBarController()
        
        // Register global keyboard shortcuts
        HotkeyManager.shared.registerDefaultHotkeys { [weak self] action in
            self?.handleHotkeyAction(action)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAllHotkeys()
    }
    
    private func handleHotkeyAction(_ action: HotkeyAction) {
        switch action {
        case .captureWithDefaultEngine:
            statusBarController?.startScreenCapture()
        case .showQuickCaptureMenu:
            statusBarController?.showQuickCaptureMenu()
        }
    }
    
    func showSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "MultiOCR Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            settingsWindow?.setContentSize(NSSize(width: 600, height: 500))
            settingsWindow?.center()
            settingsWindow?.delegate = self
            settingsWindow?.isReleasedWhenClosed = false
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }
}

enum HotkeyAction {
    case captureWithDefaultEngine
    case showQuickCaptureMenu
}
