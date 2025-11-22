//
//  SettingsManager.swift
//  MultiOCR
//
//  Manages app settings and API keys
//

import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    private let keychain = KeychainHelper.shared
    
    // Keys
    private let defaultEngineKey = "defaultOCREngine"
    private let autoCopyKey = "autoCopyToClipboard"
    private let geminiKeyName = "geminiAPIKey"
    private let openAIKeyName = "openAIAPIKey"
    private let mistralKeyName = "mistralAPIKey"
    
    private init() {}
    
    // MARK: - General Settings
    
    var defaultEngine: OCREngineType {
        get {
            let rawValue = defaults.integer(forKey: defaultEngineKey)
            return OCREngineType(rawValue: rawValue) ?? .vision
        }
        set {
            defaults.set(newValue.rawValue, forKey: defaultEngineKey)
        }
    }
    
    var autoCopyToClipboard: Bool {
        get {
            return defaults.bool(forKey: autoCopyKey)
        }
        set {
            defaults.set(newValue, forKey: autoCopyKey)
        }
    }
    
    // MARK: - API Keys
    
    var geminiAPIKey: String? {
        get {
            return keychain.get(geminiKeyName)
        }
        set {
            if let value = newValue, !value.isEmpty {
                keychain.set(value, forKey: geminiKeyName)
            } else {
                keychain.delete(geminiKeyName)
            }
        }
    }
    
    var openAIAPIKey: String? {
        get {
            return keychain.get(openAIKeyName)
        }
        set {
            if let value = newValue, !value.isEmpty {
                keychain.set(value, forKey: openAIKeyName)
            } else {
                keychain.delete(openAIKeyName)
            }
        }
    }
    
    var mistralAPIKey: String? {
        get {
            return keychain.get(mistralKeyName)
        }
        set {
            if let value = newValue, !value.isEmpty {
                keychain.set(value, forKey: mistralKeyName)
            } else {
                keychain.delete(mistralKeyName)
            }
        }
    }
}
