import Foundation
import Vision
import AppKit
import NaturalLanguage

class VisionEngine: OCREngine {
    var name = "Apple Vision"
    var isEnabled = true
    
    func recognizeText(from image: NSImage) async throws -> OCRResult {
        let startTime = Date()
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // First, try to detect language with fast recognition
            let fastRequest = VNRecognizeTextRequest()
            fastRequest.recognitionLevel = .fast
            fastRequest.automaticallyDetectsLanguage = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            // Detect language first
            var detectedLanguages: [String] = []
            do {
                try handler.perform([fastRequest])
                if let observations = fastRequest.results {
                    let sampleText = observations.prefix(5).compactMap { 
                        $0.topCandidates(1).first?.string 
                    }.joined(separator: " ")
                    
                    if !sampleText.isEmpty {
                        let recognizer = NLLanguageRecognizer()
                        recognizer.processString(sampleText)
                        if let dominantLanguage = recognizer.dominantLanguage {
                            detectedLanguages = convertNLLanguageToVisionLanguages(dominantLanguage)
                        }
                    }
                }
            } catch {
                // If fast detection fails, continue with default languages
            }
            
            // Now perform accurate recognition with detected languages
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(text: "", confidence: 0, language: nil, processingTime: Date().timeIntervalSince(startTime), engine: self.name))
                    return
                }
                
                // Extract text blocks with bounding boxes
                var textBlocks: [TextBlock] = []
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        // VNRecognizedTextObservation.boundingBox is normalized (0-1)
                        // We need to convert to image coordinates
                        let bbox = observation.boundingBox
                        
                        // Vision uses bottom-left origin, convert to top-left
                        let convertedRect = CGRect(
                            x: bbox.origin.x,
                            y: 1.0 - bbox.origin.y - bbox.height,
                            width: bbox.width,
                            height: bbox.height
                        )
                        
                        textBlocks.append(TextBlock(
                            text: candidate.string,
                            boundingBox: convertedRect,
                            confidence: candidate.confidence
                        ))
                    }
                }
                
                let avgConfidence = textBlocks.reduce(0.0) { $0 + $1.confidence } / Float(max(1, textBlocks.count))
                
                // Detect final language from full text
                let fullText = textBlocks.map { $0.text }.joined(separator: "\n")
                let detectedLanguage = self.detectLanguage(from: fullText)
                
                let result = OCRResult(
                    textBlocks: textBlocks,
                    confidence: avgConfidence,
                    language: detectedLanguage,
                    processingTime: Date().timeIntervalSince(startTime),
                    engine: self.name
                )
                
                continuation.resume(returning: result)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            
            // Set recognition languages based on detection or use comprehensive list
            if !detectedLanguages.isEmpty {
                request.recognitionLanguages = detectedLanguages
            } else {
                // Comprehensive language list with Korean prioritized
                request.recognitionLanguages = [
                    "ko-KR",    // Korean - prioritized
                    "en-US",    // English
                    "ja-JP",    // Japanese
                    "zh-Hans",  // Simplified Chinese
                    "zh-Hant",  // Traditional Chinese
                    "fr-FR",    // French
                    "de-DE",    // German
                    "es-ES",    // Spanish
                    "it-IT",    // Italian
                    "pt-BR",    // Portuguese
                    "ru-RU",    // Russian
                    "ar-SA",    // Arabic
                    "th-TH"     // Thai
                ]
            }
            
            // Re-perform with accurate settings
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func convertNLLanguageToVisionLanguages(_ language: NLLanguage) -> [String] {
        switch language {
        case .korean: return ["ko-KR", "en-US"]
        case .japanese: return ["ja-JP", "en-US"]
        case .simplifiedChinese: return ["zh-Hans", "en-US"]
        case .traditionalChinese: return ["zh-Hant", "en-US"]
        case .french: return ["fr-FR", "en-US"]
        case .german: return ["de-DE", "en-US"]
        case .spanish: return ["es-ES", "en-US"]
        case .italian: return ["it-IT", "en-US"]
        case .portuguese: return ["pt-BR", "en-US"]
        case .russian: return ["ru-RU", "en-US"]
        case .arabic: return ["ar-SA", "en-US"]
        case .thai: return ["th-TH", "en-US"]
        default: return ["en-US"]
        }
    }
    
    private func detectLanguage(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        if let dominantLanguage = recognizer.dominantLanguage {
            return dominantLanguage.rawValue
        }
        
        return nil
    }
}
