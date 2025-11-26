import Foundation
import AppKit

class GeminiCLIEngine: OCREngine {
    var name = "Gemini CLI"
    var isEnabled = false

    private let defaults = UserDefaults.standard

    private var cliPath: String {
        // Priority: 1. User Setting, 2. Auto-detected Path, 3. Default Fallback
        if let userPath = defaults.string(forKey: "geminiCLIPath"), !userPath.isEmpty {
            return userPath
        }
        if let autoPath = GeminiIDEConnection.shared.findGeminiExecutable() {
            return autoPath
        }
        return "/usr/local/bin/gemini"
    }

    private var selectedModel: String {
        defaults.string(forKey: "selected_gemini_cli_model") ?? "gemini-2.5-flash"
    }

    func recognizeText(from image: NSImage) async throws -> OCRResult {
        // This will be called by OCRManager with Vision bboxes
        fatalError("Use recognizeText(from:visionBboxes:) for Gemini CLI")
    }

    func recognizeText(from image: NSImage, visionBboxes: [TextBlock]) async throws -> OCRResult {
        let startTime = Date()

        // Resolve CLI URL
        let resolvedCliPath = self.cliPath
        let cliURL = URL(fileURLWithPath: resolvedCliPath)
        
        // Check if executable exists
        guard FileManager.default.fileExists(atPath: resolvedCliPath) else {
             throw NSError(domain: "GeminiCLIEngine", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Gemini CLI executable not found at '\(resolvedCliPath)'. Please install it or select the correct path in Settings."
            ])
        }

        // Start accessing security-scoped resource if it's a user-selected bookmark
        // Note: Auto-detected paths don't need security scope if they are standard system paths,
        // but if the user selected it via open panel, we might need it.
        // For simplicity, we try to access if it's a bookmark, but here we are using path string.
        // If we strictly rely on bookmarks for sandbox, we might need to revisit this.
        // However, since we are running /bin/sh, we are bypassing some direct execution restrictions.
        
        // Retain existing bookmark logic if available for the specific path?
        // The previous code relied on `SettingsViewModel.shared.getGeminiCLIURL()`.
        // We should probably try that first if it matches the path.
        
        var bookmarkURL: URL?
        if let savedURL = await SettingsViewModel.shared.getGeminiCLIURL(), savedURL.path == resolvedCliPath {
            bookmarkURL = savedURL
        }
        
        if let url = bookmarkURL {
             guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "GeminiCLIEngine", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to access Gemini CLI. Please select it again in Settings."
                ])
            }
        }
        defer { bookmarkURL?.stopAccessingSecurityScopedResource() }

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

        // Save image to workspace using GeminiIDEConnection
        let imageFilename = "gemini_ocr_\(UUID().uuidString).jpg"
        let imagePath: String
        
        do {
            imagePath = try GeminiIDEConnection.shared.saveFileToWorkspace(data: resizedJpegData, filename: imageFilename)
        } catch {
            throw NSError(domain: "GeminiCLIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save temporary image: \(error.localizedDescription)"])
        }
        
        // Ensure temp file is cleaned up
        defer {
            GeminiIDEConnection.shared.removeFileFromWorkspace(filename: imageFilename)
        }
        
        // Execute Gemini CLI with explicit image path
        let process = Process()
        // Use /bin/sh to execute the CLI (workaround for sandbox restrictions)
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        // Set CWD to the workspace directory so CLI considers the image "in workspace"
        process.currentDirectoryURL = URL(fileURLWithPath: GeminiIDEConnection.shared.workspacePath)

        // Pass prompt and RELATIVE image path (filename only) as arguments using -p flag and @ prefix
        // Usage: gemini -m model -p "prompt @image.jpg"
        // The CLI will resolve @image.jpg relative to the CWD (workspacePath)
        
        // Build command string using positional parameters to avoid escaping issues
        // $1: CLI Path
        // $2: Model
        // $3: Prompt
        // $4: Image Filename
        let commandString = "\"$1\" -m \"$2\" -p \"$3 @$4\""

        // Arguments for sh -c:
        // 0: -c
        // 1: commandString
        // 2: "gemini-wrapper" (becomes $0 inside sh)
        // 3: cliURL.path (becomes $1)
        // 4: selectedModel (becomes $2)
        // 5: prompt (becomes $3)
        // 6: imageFilename (becomes $4)
        process.arguments = ["-c", commandString, "gemini-wrapper", cliURL.path, selectedModel, prompt, imageFilename]

        print("Gemini CLI Command: \(cliURL.path) -m \(selectedModel) -p \"[PROMPT] @\(imageFilename)\" (CWD: \(GeminiIDEConnection.shared.workspacePath))")
        
        // Set up environment using GeminiIDEConnection
        process.environment = GeminiIDEConnection.shared.getEnvironment()
        
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
        
        // Execute process asynchronously
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                // Clean up handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                // Read any remaining data
                outputData.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                errorData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    if !output.isEmpty {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "GeminiCLIEngine", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "Gemini CLI returned empty output. Error: \(errorOutput)"
                        ]))
                    }
                } else {
                    // Handle Sandbox permission error (exit code 126)
                    if process.terminationStatus == 126 {
                        continuation.resume(throwing: NSError(domain: "GeminiCLIEngine", code: 126, userInfo: [
                            NSLocalizedDescriptionKey: "Permission Denied (Sandbox Restriction)",
                            NSLocalizedFailureReasonErrorKey: "The app cannot execute the auto-detected Gemini CLI due to macOS App Sandbox restrictions.\n\nPlease go to Settings > Gemini CLI and manually select the 'gemini' executable using the 'Browse' button to grant permission."
                        ]))
                        return
                    }
                    
                    var errorMessage = "CLI Error (exit code \(process.terminationStatus))"
                    if !errorOutput.isEmpty {
                        errorMessage += ": \(errorOutput)"
                    } else if output.isEmpty {
                        errorMessage += ": No output received from Gemini CLI"
                    } else {
                        errorMessage += ": Unexpected error. Output: \(output.prefix(200))..."
                    }
                    
                    continuation.resume(throwing: NSError(domain: "GeminiCLIEngine", code: Int(process.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: errorMessage,
                        NSLocalizedFailureReasonErrorKey: errorOutput.isEmpty ? "Unknown" : errorOutput
                    ]))
                }
            }
            
            // Timeout handling (60 seconds)
            Task {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
        let output = String(data: outputData, encoding: .utf8) ?? ""

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
