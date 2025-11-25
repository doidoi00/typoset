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
        
        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""


        if process.terminationStatus != 0 {
            // On error, read stderr for debugging
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw NSError(domain: "GeminiCLIEngine", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "CLI Error: \(errorOutput)"])
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
                // JSON parsing failed - fallback to line-by-line matching
                print("Gemini CLI JSON parsing failed: \(error.localizedDescription)")
                print("Response was: \(cleanedText)")
            }
        }

        // Fallback if JSON parsing fails (same as GeminiEngine)
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

// Gemini CLI region response (same structure as GeminiEngine)
struct GeminiCLIRegion: Codable {
    let region: Int
    let text: String
}
