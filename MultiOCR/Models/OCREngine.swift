//
//  OCREngine.swift
//  MultiOCR
//
//  Protocol and types for OCR engines
//

import Foundation
import AppKit

// MARK: - OCR Engine Type
enum OCREngineType: Int, CaseIterable {
    case vision = 0
    case gemini = 1
    case chatgpt = 2
    case mistral = 3
    
    var displayName: String {
        switch self {
        case .vision: return "Apple Vision (Local)"
        case .gemini: return "Gemini Vision AI"
        case .chatgpt: return "ChatGPT Vision"
        case .mistral: return "Mistral OCR"
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .vision: return false
        case .gemini, .chatgpt, .mistral: return true
        }
    }
}

// MARK: - OCR Engine Protocol
protocol OCREngine {
    var engineType: OCREngineType { get }
    func performOCR(on image: NSImage, completion: @escaping (Result<String, OCRError>) -> Void)
}

// MARK: - OCR Error
enum OCRError: LocalizedError {
    case invalidImage
    case apiKeyMissing
    case networkError(Error)
    case apiError(String)
    case processingFailed(String)
    case unsupportedEngine
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image provided"
        case .apiKeyMissing:
            return "API key is missing. Please configure it in Settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .processingFailed(let reason):
            return "OCR processing failed: \(reason)"
        case .unsupportedEngine:
            return "Unsupported OCR engine"
        }
    }
}
