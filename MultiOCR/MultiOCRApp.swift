//
//  MultiOCRApp.swift
//  MultiOCR
//
//  Main application entry point for the menubar OCR app
//

import SwiftUI

@main
struct MultiOCRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
