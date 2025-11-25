import Foundation
import AppKit
import Combine

class OCRManager: ObservableObject {
    static let shared = OCRManager()
    
    @Published var engines: [OCREngine] = []
    @Published var currentEngine: OCREngine?
    
    private let visionEngine = VisionEngine()
    
    private init() {
        setupEngines()
    }
    
    private func setupEngines() {
        let gemini = GeminiEngine()
        let openai = OpenAIEngine()
        let mistral = MistralEngine()
        let geminiCLI = GeminiCLIEngine()
        engines = [visionEngine, gemini, openai, mistral, geminiCLI]
        currentEngine = visionEngine
    }
    
    func performOCR(on image: NSImage) async throws -> OCRResult {
        guard let engine = currentEngine else {
            throw NSError(domain: "OCRManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No engine selected"])
        }
        
        // Hybrid mode: If Gemini, Gemini CLI, or GPT is selected, run Vision first for bboxes
        if engine.name == "Gemini" || engine.name == "Gemini CLI" || engine.name == "GPT" {
            // Step 1: Run Vision OCR to get bounding boxes
            let visionResult = try await visionEngine.recognizeText(from: image)

            // Step 2: Pass Vision's bboxes to AI engine for accurate text recognition
            if let geminiEngine = engine as? GeminiEngine {
                return try await geminiEngine.recognizeText(from: image, visionBboxes: visionResult.textBlocks)
            } else if let geminiCLIEngine = engine as? GeminiCLIEngine {
                return try await geminiCLIEngine.recognizeText(from: image, visionBboxes: visionResult.textBlocks)
            } else if let openAIEngine = engine as? OpenAIEngine {
                return try await openAIEngine.recognizeText(from: image, visionBboxes: visionResult.textBlocks)
            }
        }
        
        // Standard mode for other engines
        return try await engine.recognizeText(from: image)
    }
    
    func setEngine(named name: String) {
        if let engine = engines.first(where: { $0.name == name }) {
            currentEngine = engine
        }
    }
}
