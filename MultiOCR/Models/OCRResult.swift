//
//  OCRResult.swift
//  MultiOCR
//
//  Data model for OCR results
//

import Foundation
import AppKit

struct OCRResult: Codable {
    let id: UUID
    let text: String
    let engine: String
    let timestamp: Date
    let thumbnailData: Data?
    
    init(text: String, engine: OCREngineType, image: NSImage? = nil) {
        self.id = UUID()
        self.text = text
        self.engine = engine.displayName
        self.timestamp = Date()
        
        // Create thumbnail
        if let image = image,
           let thumbnail = image.resized(to: NSSize(width: 100, height: 100)),
           let tiffData = thumbnail.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData) {
            self.thumbnailData = bitmapImage.representation(using: .png, properties: [:])
        } else {
            self.thumbnailData = nil
        }
    }
}

extension NSImage {
    func resized(to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        let sourceRect = NSRect(origin: .zero, size: self.size)
        let destRect = NSRect(origin: .zero, size: newSize)
        
        self.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
}
