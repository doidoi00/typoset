import Foundation
import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine

@MainActor
class ScreenCaptureManager: ObservableObject {
    static let shared = ScreenCaptureManager()
    
    @Published var isCapturing = false
    private var overlayWindow: SelectionOverlayWindow?
    
    var onCapture: ((NSImage) -> Void)?
    
    func startCapture(completion: @escaping (NSImage) -> Void) {
        guard !isCapturing else { return }
        
        Task {
            let hasPermission = await checkPermission()
            guard hasPermission else {
                // 권한이 없을 경우 사용자에게 알림 (예: 설정 앱 열기 안내)
                print("❌ Screen recording permission not granted.")
                // 여기서 사용자에게 권한이 필요하다는 대화 상자를 표시 할 수 있습니다.
                return
            }
            
            DispatchQueue.main.async {
                self.isCapturing = true
                self.onCapture = completion
                self.showOverlay()
            }
        }
    }
    
    func checkPermission() async -> Bool {
        // SCShareableContent.current를 호출하기 전에 권한 상태를 미리 확인할 수 있습니다.
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        
        // 권한을 요청합니다. 사용자가 처음으로 이 작업을 수행하면 프롬프트가 표시됩니다.
        return CGRequestScreenCaptureAccess()
    }
    
    private func showOverlay() {
        if let screen = NSScreen.main {
            let window = SelectionOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            
            let view = OverlayView { [weak self] rect in
                Task {
                    await self?.captureRegion(rect)
                }
            } onCancel: { [weak self] in
                self?.stopCapture()
            }
            
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
            self.overlayWindow = window
            
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func captureRegion(_ rect: CGRect) async {
        // 캡처하기 전에 오버레이를 숨 깁니다.
        DispatchQueue.main.async {
            self.overlayWindow?.orderOut(self)
        }
        
        do {
            // ScreenCaptureKit를 사용하여 스크린샷을 캡처합니다.
            guard let currentApp = await findCurrentSCApplication(),
                  let display = try await SCShareableContent.current.displays.first(where: { $0.displayID == NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }) else {
                print("❌ Could not get sharable content.")
                stopCapture()
                return
            }
            
            let filter = SCContentFilter(display: display, excludingApplications: [currentApp], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = rect
            config.width = Int(rect.width) * Int(NSScreen.main?.backingScaleFactor ?? 1)
            config.height = Int(rect.height) * Int(NSScreen.main?.backingScaleFactor ?? 1)
            
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: image, size: rect.size)
            
            print("✅ Screen captured successfully. Size: \(rect.size)")
            
            DispatchQueue.main.async {
                self.onCapture?(nsImage)
                self.stopCapture()
            }
        } catch {
            print("❌ Error capturing screenshot: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.stopCapture()
            }
        }
    }
    
    private func findCurrentSCApplication() async -> SCRunningApplication? {
        do {
            let apps = try await SCShareableContent.current.applications
            let currentPID = NSRunningApplication.current.processIdentifier
            return apps.first { $0.processID == currentPID }
        } catch {
            print("Error fetching applications: \(error)")
            return nil
        }
    }
    
    func stopCapture() {
        isCapturing = false
        overlayWindow?.close()
        overlayWindow = nil
        onCapture = nil
    }
}


