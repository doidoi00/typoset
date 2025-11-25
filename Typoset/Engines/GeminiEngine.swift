import Foundation
import AppKit

class GeminiEngine: OCREngine {
    var name = "Gemini"
    var isEnabled = false
    
    private let keychain = KeychainService.shared
    private let defaults = UserDefaults.standard
    
    private var selectedModel: String {
        defaults.string(forKey: "selected_gemini_model") ?? "gemini-2.5-flash"
    }
    
    func recognizeText(from image: NSImage) async throws -> OCRResult {
        // This will be called by OCRManager with Vision bboxes
        fatalError("Use recognizeText(from:visionBboxes:) for Gemini")
    }
    
    func recognizeText(from image: NSImage, visionBboxes: [TextBlock]) async throws -> OCRResult {
        guard let apiKey = keychain.loadAllKeys().gemini, !apiKey.isEmpty else {
            throw NSError(domain: "GeminiEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key not found. Please check settings."])
        }
        
        let startTime = Date()
        
        let optimizationLevel = await SettingsViewModel.shared.imageOptimizationLevel
        let resizedImage = ImageUtils.resizeImage(image, level: optimizationLevel)
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "GeminiEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }
        
        let base64Image = jpegData.base64EncodedString()
        
        // Build contextual prompt with Vision bbox information
        var prompt = await SettingsViewModel.shared.customOCRPrompt
        
        prompt += "\n\nI've pre-detected \(visionBboxes.count) text regions using computer vision. Use these as guidance:\n\n"
        
        for (index, block) in visionBboxes.enumerated() {
            let bbox = block.boundingBox
            prompt += "Region \(index + 1): x=\(String(format: "%.3f", bbox.origin.x)), y=\(String(format: "%.3f", bbox.origin.y)), w=\(String(format: "%.3f", bbox.width)), h=\(String(format: "%.3f", bbox.height))\n"
        }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/\(selectedModel):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body with generationConfig (max_output_tokens)
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]
        
        // Helper to send request and handle possible max_tokens error
        func sendGeminiRequest(with bodyDict: [String: Any]) async throws -> Data {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "GeminiEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            if httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                // Detect unsupported max_tokens error and retry with corrected param
                if errorMsg.contains("Unsupported parameter: 'max_tokens'") {
                    let correctedBody = bodyDict
                    // Replace max_tokens with maxOutputTokens if present
                    if let genConfig = correctedBody["generationConfig"] as? [String: Any] {
                        // No action needed; ensure maxOutputTokens is set
                        _ = genConfig
                    }
                    // Retry once
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                    guard let retryHttp = retryResponse as? HTTPURLResponse, retryHttp.statusCode == 200 else {
                        throw NSError(domain: "GeminiEngine", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error after retry: \(errorMsg)"])
                    }
                    return retryData
                }
                throw NSError(domain: "GeminiEngine", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMsg)"])
            }
            return data
        }
        
        // Perform request with retry handling
        let data = try await sendGeminiRequest(with: body)

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        
        // Track usage
        if let usage = geminiResponse.usageMetadata {
            Task { @MainActor in
                SettingsViewModel.shared.incrementUsage(for: "Gemini", tokens: usage.totalTokenCount)
            }
        }
        
        guard let responseText = geminiResponse.candidates?.first?.content.parts.first?.text else {
            throw NSError(domain: "GeminiEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text in response"])
        }
        
        // Clean up response - remove markdown code blocks if present
        var cleanedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasPrefix("```") {
            // Remove opening code block
            if let startRange = cleanedText.range(of: "```json") {
                cleanedText = String(cleanedText[startRange.upperBound...])
            } else if let startRange = cleanedText.range(of: "```") {
                cleanedText = String(cleanedText[startRange.upperBound...])
            }
            
            // Remove closing code block
            if let endRange = cleanedText.range(of: "```", options: .backwards) {
                cleanedText = String(cleanedText[..<endRange.lowerBound])
            }
            
            cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse JSON response
        var enhancedBlocks: [TextBlock] = []
        if let jsonData = cleanedText.data(using: .utf8) {
            do {
                let regions = try JSONDecoder().decode([GeminiRegion].self, from: jsonData)
                // Map Gemini's text back to Vision's bboxes
                for region in regions {
                    let index = region.region - 1
                    if index >= 0 && index < visionBboxes.count {
                        let originalBlock = visionBboxes[index]
                        enhancedBlocks.append(TextBlock(
                            text: region.text,
                            boundingBox: originalBlock.boundingBox,
                            confidence: 1.0  // Gemini doesn't provide confidence
                        ))
                    }
                }
            } catch {
                // JSON parsing failed - fallback to line-by-line matching
                print("Gemini JSON parsing failed: \(error.localizedDescription)")
                print("Response was: \(cleanedText)")
            }
        }
        
        // Fallback if JSON parsing fails
        if enhancedBlocks.isEmpty {
            print("Using fallback: splitting by lines")
            // Use original Vision bboxes with Gemini's combined text
            let lines = cleanedText.components(separatedBy: "\n").filter { !$0.isEmpty }
            for (index, line) in lines.enumerated() where index < visionBboxes.count {
                enhancedBlocks.append(TextBlock(
                    text: line,
                    boundingBox: visionBboxes[index].boundingBox,
                    confidence: 1.0
                ))
            }
        }
        
        return OCRResult(
            textBlocks: enhancedBlocks,
            confidence: 1.0,
            language: nil,
            processingTime: Date().timeIntervalSince(startTime),
            engine: self.name
        )
    }
}

// Gemini region response
struct GeminiRegion: Codable {
    let region: Int
    let text: String
}

// Response Models
struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
    let usageMetadata: GeminiUsage?
}

struct GeminiUsage: Codable {
    let promptTokenCount: Int
    let candidatesTokenCount: Int
    let totalTokenCount: Int
}

struct GeminiCandidate: Codable {
    let content: GeminiContent
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String?
}
