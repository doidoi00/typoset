import Foundation
import AppKit

class MistralEngine: OCREngine {
    var name = "Mistral"
    var isEnabled = false
    
    private let keychain = KeychainService.shared
    private let defaults = UserDefaults.standard
    
    private var model: String {
        defaults.string(forKey: "selectedMistralModel") ?? "mistral-ocr-latest"
    }
    
    func recognizeText(from image: NSImage) async throws -> OCRResult {
        let apiKey = await SettingsViewModel.shared.mistralKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "MistralEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key not found. Please check settings."])
        }
        
        let startTime = Date()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "MistralEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }
        
        let base64Image = jpegData.base64EncodedString()
        
        let url = URL(string: "https://api.mistral.ai/v1/ocr")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": model,
            "document": [
                "image_url": "data:image/jpeg;base64,\(base64Image)"
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "MistralEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
             let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
             throw NSError(domain: "MistralEngine", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMsg)"])
        }
        
        let mistralResponse = try JSONDecoder().decode(MistralOCRResponse.self, from: data)
        
        // Track usage
        if let usage = mistralResponse.usageInfo {
            Task { @MainActor in
                SettingsViewModel.shared.incrementUsage(for: "Mistral", tokens: usage.totalTokenCount)
            }
        } else {
            // Mistral OCR responses may omit usage; nothing to increment
            print("Mistral OCR response had no usage block; skipping token tracking.")
        }
        
        // Mistral OCR returns pages with markdown. We'll join them and remove image references.
        let text = mistralResponse.pages.map { page in
            // Remove markdown image syntax: ![alt-text](image.jpg)
            page.markdown.replacingOccurrences(
                of: #"!\[.*?\]\(.*?\)"#,
                with: "",
                options: .regularExpression
            )
        }.joined(separator: "\n\n---\n\n")
        
        return OCRResult(
            text: text,
            confidence: 1.0, // Mistral does not provide confidence scores
            language: nil,
            processingTime: Date().timeIntervalSince(startTime),
            engine: self.name
        )
    }
}

// Response Models
struct MistralOCRResponse: Codable {
    let pages: [MistralPage]
    let usageInfo: MistralUsage?
    
    enum CodingKeys: String, CodingKey {
        case pages
        case usageInfo = "usage_info"
    }
}

struct MistralUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    // According to docs.mistral.ai/api, usage includes prompt_tokens and completion_tokens.
    // Some responses may also include total_tokens; fall back to sum when absent.
    var totalTokenCount: Int {
        if let totalTokens { return totalTokens }
        return (promptTokens ?? 0) + (completionTokens ?? 0)
    }
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct MistralPage: Codable {
    let index: Int
    let markdown: String
    let images: [MistralImage]?
}

struct MistralImage: Codable {
    let id: String
    let image_base64: String?
}
