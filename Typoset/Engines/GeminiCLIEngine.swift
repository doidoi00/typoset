import Foundation
import AppKit

class GeminiCLIEngine: OCREngine {
    var name = "Gemini CLI"
    var isEnabled = false

    private let defaults = UserDefaults.standard

    private var cliPath: String {
        defaults.string(forKey: "geminiCLIPath") ?? "/usr/local/bin/gemini"
    }

    private var selectedModel: String {
        defaults.string(forKey: "selected_gemini_cli_model") ?? "gemini-2.5-flash"
    }

    func recognizeText(from image: NSImage) async throws -> OCRResult {
        // This will be called by OCRManager with Vision bboxes
        fatalError("Use recognizeText(from:visionBboxes:) for Gemini CLI")
    }

    func recognizeText(from image: NSImage, visionBboxes: [TextBlock]) async throws -> OCRResult {
        guard FileManager.default.fileExists(atPath: cliPath) else {
            throw NSError(domain: "GeminiCLIEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Gemini CLI executable not found at \(cliPath). Please check settings."])
        }

        let startTime = Date()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let _ = bitmap.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "GeminiCLIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }
        
        let optimizationLevel = await SettingsViewModel.shared.imageOptimizationLevel
        let resizedImage = ImageUtils.resizeImage(image, level: optimizationLevel)
        
        guard let resizedTiffData = resizedImage.tiffRepresentation,
              let resizedBitmap = NSBitmapImageRep(data: resizedTiffData),
              let resizedJpegData = resizedBitmap.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "GeminiCLIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process resized image"])
        }

        // Build contextual prompt with Vision bbox information (same as GeminiEngine)
        var prompt = await SettingsViewModel.shared.customOCRPrompt
        
        prompt += "\n\nI've pre-detected \(visionBboxes.count) text regions using computer vision. Use these as guidance:\n\n"
        
        for (index, block) in visionBboxes.enumerated() {
            let bbox = block.boundingBox
            prompt += "Region \(index + 1): x=\(String(format: "%.3f", bbox.origin.x)), y=\(String(format: "%.3f", bbox.origin.y)), w=\(String(format: "%.3f", bbox.width)), h=\(String(format: "%.3f", bbox.height))\n"
        }

        // Save image to temporary file to ensure CLI processes the correct image
        let tempDir = FileManager.default.temporaryDirectory
        let imagePath = tempDir.appendingPathComponent("gemini_ocr_\(UUID().uuidString).jpg").path
        
        do {
            try resizedJpegData.write(to: URL(fileURLWithPath: imagePath))
        } catch {
            throw NSError(domain: "GeminiCLIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save temporary image: \(error.localizedDescription)"])
        }
        
        // Ensure temp file is cleaned up
        defer {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        
        // Execute Gemini CLI with explicit image path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        
        // Set CWD to the temp directory so CLI considers the image "in workspace"
        process.currentDirectoryURL = tempDir
        
        // Pass prompt and RELATIVE image path (filename only) as arguments using -p flag and @ prefix
        // Usage: gemini -m model -p "prompt @image.jpg"
        // The CLI will resolve @image.jpg relative to the CWD (tempDir)
        let imageFilename = URL(fileURLWithPath: imagePath).lastPathComponent
        process.arguments = [
            "-m", selectedModel,
            "-p", "\(prompt) @\(imageFilename)"
        ]
        
        print("Gemini CLI Command: \(cliPath) -m \(selectedModel) -p \"[PROMPT] @\(imageFilename)\" (CWD: \(tempDir.path))")
        
        // Set up environment with common PATH locations
        var environment = ProcessInfo.processInfo.environment
        let additionalPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            (environment["HOME"] ?? "") + "/.nvm/versions/node/*/bin"
        ]
        
        let currentPath = environment["PATH"] ?? ""
        let newPath = (additionalPaths + currentPath.split(separator: ":").map(String.init)).joined(separator: ":")
        environment["PATH"] = newPath
        process.environment = environment
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Improvement 2: Streaming output processing
        var outputData = Data()
        var errorData = Data()
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputData.append(handle.availableData)
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorData.append(handle.availableData)
        }
        
        try process.run()
        
        // Improvement 1: Add timeout (60 seconds for OCR processing)
        let timeout = DispatchTime.now() + .seconds(60)
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }
        
        if semaphore.wait(timeout: timeout) == .timedOut {
            process.terminate()
            // Clean up handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw NSError(domain: "GeminiCLIEngine", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Gemini CLI timed out after 60 seconds. The image may be too complex or the service is slow."
            ])
        }
        
        // Clean up handlers after process completes
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        
        // Read any remaining data
        outputData.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        // Improvement 3: Enhanced error handling
        if process.terminationStatus != 0 {
            var errorMessage = "CLI Error (exit code \(process.terminationStatus))"
            
            if !errorOutput.isEmpty {
                errorMessage += ": \(errorOutput)"
            } else if output.isEmpty {
                errorMessage += ": No output received from Gemini CLI"
            } else {
                errorMessage += ": Unexpected error. Output: \(output.prefix(200))..."
            }
            
            throw NSError(domain: "GeminiCLIEngine", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errorMessage,
                NSLocalizedFailureReasonErrorKey: errorOutput.isEmpty ? "Unknown" : errorOutput
            ])
        }
        
        // Validate output is not empty
        guard !output.isEmpty else {
            throw NSError(domain: "GeminiCLIEngine", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Gemini CLI returned empty output. Error: \(errorOutput)"
            ])
        }

        // Clean up response - remove markdown code blocks if present (same as GeminiEngine)
        var cleanedText = output.trimmingCharacters(in: .whitespacesAndNewlines)
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
                let regions = try JSONDecoder().decode([GeminiCLIRegion].self, from: jsonData)
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
                // Improvement 3: Enhanced error logging for JSON parsing failures
                print("[GeminiCLIEngine] JSON parsing failed: \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("[GeminiCLIEngine] Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .typeMismatch(let type, let context):
                        print("[GeminiCLIEngine] Type mismatch for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .valueNotFound(let type, let context):
                        print("[GeminiCLIEngine] Value not found for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .dataCorrupted(let context):
                        print("[GeminiCLIEngine] Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    @unknown default:
                        print("[GeminiCLIEngine] Unknown decoding error")
                    }
                }
                print("[GeminiCLIEngine] Response preview (first 500 chars): \(cleanedText.prefix(500))")
                if cleanedText.count > 500 {
                    print("[GeminiCLIEngine] ... (truncated \(cleanedText.count - 500) more characters)")
                }
            }
        }

        // Fallback if JSON parsing fails (same as GeminiEngine)
        if enhancedBlocks.isEmpty {
            print("[GeminiCLIEngine] Using fallback: splitting by lines (\(visionBboxes.count) regions available)")
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

// Gemini CLI region response (same structure as GeminiEngine)
struct GeminiCLIRegion: Codable {
    let region: Int
    let text: String
}
