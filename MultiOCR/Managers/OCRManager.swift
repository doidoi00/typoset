//
//  OCRManager.swift
//  MultiOCR
//
//  Coordinates OCR operations across different engines
//

import Foundation
import AppKit

class OCRManager {
    static let shared = OCRManager()
    
    private var engines: [OCREngineType: OCREngine] = [:]
    private var recentResults: [OCRResult] = []
    private let maxRecentResults = 10
    
    private init() {
        // Initialize all engines
        engines[.vision] = VisionOCREngine()
        engines[.gemini] = GeminiOCREngine()
        engines[.chatgpt] = ChatGPTOCREngine()
        engines[.mistral] = MistralOCREngine()
        
        // Load recent results from disk
        loadRecentResults()
    }
    
    func performOCR(on image: NSImage, using engineType: OCREngineType, completion: @escaping (Result<OCRResult, OCRError>) -> Void) {
        guard let engine = engines[engineType] else {
            completion(.failure(.unsupportedEngine))
            return
        }
        
        engine.performOCR(on: image) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    let ocrResult = OCRResult(text: text, engine: engineType, image: image)
                    self?.addRecentResult(ocrResult)
                    completion(.success(ocrResult))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func getRecentResults(limit: Int = 5) -> [OCRResult] {
        return Array(recentResults.prefix(limit))
    }
    
    private func addRecentResult(_ result: OCRResult) {
        recentResults.insert(result, at: 0)
        
        // Keep only the most recent results
        if recentResults.count > maxRecentResults {
            recentResults = Array(recentResults.prefix(maxRecentResults))
        }
        
        saveRecentResults()
    }
    
    private func saveRecentResults() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(recentResults) {
            UserDefaults.standard.set(encoded, forKey: "recentOCRResults")
        }
    }
    
    private func loadRecentResults() {
        if let data = UserDefaults.standard.data(forKey: "recentOCRResults") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([OCRResult].self, from: data) {
                recentResults = decoded
            }
        }
    }
}
