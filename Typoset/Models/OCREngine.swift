import Foundation
import AppKit

protocol OCREngine {
    var name: String { get }
    var isEnabled: Bool { get set }
    
    func recognizeText(from image: NSImage) async throws -> OCRResult
}
