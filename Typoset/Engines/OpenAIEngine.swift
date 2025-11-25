import Foundation
import AppKit

class OpenAIEngine: OCREngine {
    var name = "GPT"
    var isEnabled = false

    private let keychain = KeychainService.shared
    private let defaults = UserDefaults.standard

    private var selectedModel: String {
        defaults.string(forKey: "selectedOpenAIModel") ?? "gpt-4o-mini"
    }

    func recognizeText(from image: NSImage) async throws -> OCRResult {
        // This will be called by OCRManager with Vision bboxes
        fatalError("Use recognizeText(from:visionBboxes:) for OpenAI")
    }

    func recognizeText(from image: NSImage, visionBboxes: [TextBlock]) async throws -> OCRResult {
        guard let apiKey = keychain.loadAllKeys().openai, !apiKey.isEmpty else {
            throw NSError(domain: "OpenAIEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key not found. Please check settings."])
        }

        let startTime = Date()

        let optimizationLevel = await SettingsViewModel.shared.imageOptimizationLevel
        let resizedImage = ImageUtils.resizeImage(image, level: optimizationLevel)
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "OpenAIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }
        
        let base64Image = jpegData.base64EncodedString()

        // Build contextual prompt with Vision bbox information (same as GeminiEngine)
        var prompt = await SettingsViewModel.shared.customOCRPrompt
        
        prompt += "\n\nI've pre-detected \(visionBboxes.count) text regions using computer vision. Use these as guidance:\n\n"
        
        for (index, block) in visionBboxes.enumerated() {
            let bbox = block.boundingBox
            prompt += "Region \(index + 1): x=\(String(format: "%.3f", bbox.origin.x)), y=\(String(format: "%.3f", bbox.origin.y)), w=\(String(format: "%.3f", bbox.width)), h=\(String(format: "%.3f", bbox.height))\n"
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_completion_tokens": 4096
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "OpenAIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
             let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
             throw NSError(domain: "OpenAIEngine", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMsg)"])
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        // Track usage
        if let usage = openAIResponse.usage {
            Task { @MainActor in
                SettingsViewModel.shared.incrementUsage(for: "GPT", tokens: usage.total_tokens)
            }
        }

        guard let responseText = openAIResponse.choices.first?.message.content else {
            throw NSError(domain: "OpenAIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text in response"])
        }

        // Clean up response - remove markdown code blocks if present (same as GeminiEngine)
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

        // Parse JSON response (same as GeminiEngine)
        var enhancedBlocks: [TextBlock] = []
        if let jsonData = cleanedText.data(using: .utf8) {
            do {
                let regions = try JSONDecoder().decode([OpenAIRegion].self, from: jsonData)
                // Map OpenAI's text back to Vision's bboxes
                for region in regions {
                    let index = region.region - 1
                    if index >= 0 && index < visionBboxes.count {
                        let originalBlock = visionBboxes[index]
                        enhancedBlocks.append(TextBlock(
                            text: region.text,
                            boundingBox: originalBlock.boundingBox,
                            confidence: 1.0  // OpenAI doesn't provide confidence
                        ))
                    }
                }
            } catch {
                // JSON parsing failed - fallback to line-by-line matching
                print("OpenAI JSON parsing failed: \(error.localizedDescription)")
                print("Response was: \(cleanedText)")
            }
        }

        // Fallback if JSON parsing fails (same as GeminiEngine)
        if enhancedBlocks.isEmpty {
            print("Using fallback: splitting by lines")
            // Use original Vision bboxes with OpenAI's combined text
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

// OpenAI region response (same structure as GeminiEngine)
struct OpenAIRegion: Codable {
    let region: Int
    let text: String
}

// Response Models
struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIUsage: Codable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIMessage: Codable {
    let content: String
}
