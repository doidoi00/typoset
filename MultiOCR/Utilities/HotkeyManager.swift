//
//  HotkeyManager.swift
//  MultiOCR
//
//  Manages global keyboard shortcuts
//

import Foundation
import Carbon
import AppKit

class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var hotkeys: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: (HotkeyAction) -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    
    private init() {}
    
    func registerDefaultHotkeys(handler: @escaping (HotkeyAction) -> Void) {
        // Cmd+Shift+1 for default capture
        registerHotkey(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(cmdKey | shiftKey),
            action: .captureWithDefaultEngine,
            handler: handler
        )
        
        // Cmd+Shift+2 for quick capture menu
        registerHotkey(
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: UInt32(cmdKey | shiftKey),
            action: .showQuickCaptureMenu,
            handler: handler
        )
    }
    
    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, action: HotkeyAction, handler: @escaping (HotkeyAction) -> Void) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        if eventHandler == nil {
            InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                
                var hotkeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
                
                if let handler = manager.handlers[hotkeyID.id] {
                    DispatchQueue.main.async {
                        if hotkeyID.id == 1 {
                            handler(.captureWithDefaultEngine)
                        } else if hotkeyID.id == 2 {
                            handler(.showQuickCaptureMenu)
                        }
                    }
                    return noErr
                }
                
                return OSStatus(eventNotHandledErr)
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        
        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = OSType(0x4D4F4352) // 'MOCR'
        hotkeyID.id = keyCode == UInt32(kVK_ANSI_1) ? 1 : 2
        
        var hotkeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        
        if let ref = hotkeyRef {
            hotkeys[hotkeyID.id] = ref
            handlers[hotkeyID.id] = handler
        }
    }
    
    func unregisterAllHotkeys() {
        for (_, ref) in hotkeys {
            UnregisterEventHotKey(ref)
        }
        hotkeys.removeAll()
        handlers.removeAll()
        
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
