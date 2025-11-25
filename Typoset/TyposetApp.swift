import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct TyposetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var viewModel = MainViewModel()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
                .environmentObject(viewModel)
        }
        .commands {
            SidebarCommands() 
        }
        
        Settings {
            SettingsView()
        }
        
        MenuBarExtra("Typoset", systemImage: "text.viewfinder") {
            MenuBarContent(viewModel: viewModel)
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        Button("Import Image") {
            viewModel.importFile(allowedTypes: [UTType.image])
        }
        
        Button("Import PDF") {
            viewModel.importFile(allowedTypes: [UTType.pdf])
        }
        
        Divider()
        
        Button("Quick Capture") {
            viewModel.captureScreen()
        }
        .keyboardShortcut("1", modifiers: [.command, .shift])
        
        Divider()
        
        Button("Open Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Preferences")
            }
            .keyboardShortcut(",")
        } else {
            Button("Preferences") {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
        
        Divider()
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup code if needed
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Close any open panels to prevent them from staying after app quits
        NSApp.windows.forEach { window in
            if window is NSOpenPanel || window is NSSavePanel {
                window.close()
            }
        }
    }
}
