import Foundation

// MARK: - Region Protocol

/// Protocol for OCR region responses that can be parsed
public protocol RegionProtocol {
    var regionIndex: Int { get }
    var regionText: String { get }
}

// MARK: - OCR Response Parser

/// Utility for parsing OCR engine responses with markdown cleanup and JSON parsing
public struct OCRResponseParser {
    
    /// Removes markdown code blocks from response text
    /// - Parameter text: Raw response text that may contain ```json or ``` blocks
    /// - Returns: Cleaned text without markdown code blocks
    public static func cleanMarkdownCodeBlocks(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        
        return cleanedText
    }
    
    /// Parses JSON regions and maps them to Vision bounding boxes
    /// - Parameters:
    ///   - jsonString: Cleaned JSON string containing region data
    ///   - visionBboxes: Vision-detected bounding boxes to map to
    ///   - regionType: Type of region struct to decode (must conform to RegionProtocol)
    ///   - engineName: Name of the OCR engine for logging
    /// - Returns: Array of TextBlocks with parsed text and bounding boxes
    public static func parseRegionsJSON<T: Decodable & RegionProtocol>(
        _ jsonString: String,
        visionBboxes: [TextBlock],
        regionType: T.Type,
        engineName: String
    ) -> [TextBlock] {
        var enhancedBlocks: [TextBlock] = []
        
        // Try JSON parsing
        if let jsonData = jsonString.data(using: .utf8) {
            do {
                let regions = try JSONDecoder().decode([T].self, from: jsonData)
                
                // Map regions to Vision bboxes
                for region in regions {
                    let index = region.regionIndex - 1
                    if index >= 0 && index < visionBboxes.count {
                        let originalBlock = visionBboxes[index]
                        enhancedBlocks.append(TextBlock(
                            text: region.regionText,
                            boundingBox: originalBlock.boundingBox,
                            confidence: 1.0
                        ))
                    }
                }
            } catch {
                // JSON parsing failed - will use fallback
                print("\(engineName) JSON parsing failed: \(error.localizedDescription)")
                print("Response was: \(jsonString)")
            }
        }
        
        // Fallback: split by lines if JSON parsing failed
        if enhancedBlocks.isEmpty {
            print("Using fallback: splitting by lines")
            let lines = jsonString.components(separatedBy: "\n").filter { !$0.isEmpty }
            for (index, line) in lines.enumerated() where index < visionBboxes.count {
                enhancedBlocks.append(TextBlock(
                    text: line,
                    boundingBox: visionBboxes[index].boundingBox,
                    confidence: 1.0
                ))
            }
        }
        
        return enhancedBlocks
    }
}
