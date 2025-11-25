import Foundation
import CoreGraphics

public struct TextBlock {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float
}

struct OCRResult {
    let id = UUID()
    let textBlocks: [TextBlock]  // Individual text blocks with positions
    let text: String              // Combined text for compatibility
    let confidence: Float
    let language: String?
    let processingTime: TimeInterval
    let engine: String
    
    // Convenience initializer for engines that don't provide bbox
    init(text: String, confidence: Float, language: String?, processingTime: TimeInterval, engine: String) {
        self.textBlocks = []
        self.text = text
        self.confidence = confidence
        self.language = language
        self.processingTime = processingTime
        self.engine = engine
    }
    
    // Full initializer with bbox support
    init(textBlocks: [TextBlock], confidence: Float, language: String?, processingTime: TimeInterval, engine: String) {
        self.textBlocks = textBlocks
        self.text = textBlocks.map { $0.text }.joined(separator: "\n")
        self.confidence = confidence
        self.language = language
        self.processingTime = processingTime
        self.engine = engine
    }
}
