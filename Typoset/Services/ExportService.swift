import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct OCRMetadata {
    let engine: String
    let confidence: Float?
    let language: String?
    let timestamp: Date
    let source: String
    let pageCount: Int?
    
    var confidenceString: String {
        guard let conf = confidence, conf < 1.0 else {
            return "N/A"
        }
        return String(format: "%.1f%%", conf * 100)
    }
}

class ExportService {
    static let shared = ExportService()
    
    private init() {}
    
    // MARK: - Export as TXT
    func exportAsText(content: String, filename: String = "ocr-result.txt", metadata: OCRMetadata? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = filename
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            var output = ""
            
            // Add metadata header if provided
            if let meta = metadata {
                output += "# OCR Result\n"
                output += "Engine: \(meta.engine)\n"
                output += "Confidence: \(meta.confidenceString)\n"
                if let lang = meta.language {
                    output += "Language: \(lang)\n"
                }
                output += "Date: \(self.formatDate(meta.timestamp))\n"
                output += "\n---\n\n"
            }
            
            output += content
            
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    // MARK: - Export as Markdown
    func exportAsMarkdown(content: String, filename: String = "ocr-result.md", metadata: OCRMetadata? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = filename
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            var markdown = ""
            
            if let meta = metadata {
                markdown += "# OCR Result\n\n"
                markdown += "**Engine**: \(meta.engine)\n\n"
                markdown += "**Confidence**: \(meta.confidenceString)\n\n"
                if let lang = meta.language {
                    markdown += "**Language**: \(lang)\n\n"
                }
                markdown += "**Date**: \(self.formatDate(meta.timestamp))\n\n"
                if let pages = meta.pageCount, pages > 1 {
                    markdown += "**Pages**: \(pages)\n\n"
                }
                markdown += "---\n\n"
                markdown += "## Content\n\n"
            }
            
            markdown += content
            
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    // MARK: - Export as JSON
    func exportAsJSON(content: String, filename: String = "ocr-result.json", metadata: OCRMetadata? = nil, textBlocks: [TextBlock]? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = filename
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            var jsonDict: [String: Any] = [
                "text": content,
                "timestamp": ISO8601DateFormatter().string(from: metadata?.timestamp ?? Date())
            ]
            
            if let meta = metadata {
                jsonDict["engine"] = meta.engine
                if let conf = meta.confidence, conf < 1.0 {
                    jsonDict["confidence"] = conf
                }
                if let lang = meta.language {
                    jsonDict["language"] = lang
                }
                jsonDict["source"] = meta.source
                if let pages = meta.pageCount {
                    jsonDict["pageCount"] = pages
                }
            }
            
            // Include bounding boxes if available
            if let blocks = textBlocks, !blocks.isEmpty {
                let blocksData = blocks.map { block in
                    return [
                        "text": block.text,
                        "boundingBox": [
                            "x": block.boundingBox.origin.x,
                            "y": block.boundingBox.origin.y,
                            "width": block.boundingBox.width,
                            "height": block.boundingBox.height
                        ],
                        "confidence": block.confidence
                    ] as [String: Any]
                }
                jsonDict["textBlocks"] = blocksData
            }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted)
                try jsonData.write(to: url)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    // MARK: - Export as Searchable PDF
    func exportAsSearchablePDF(image: NSImage, textBlocks: [TextBlock], filename: String, metadata: OCRMetadata? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // Create PDF Context
            let pdfData = NSMutableData()
            let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
            
            // Use image size for PDF page size
            var mediaBox = CGRect(origin: .zero, size: image.size)
            
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                print("Failed to create PDF context")
                return
            }
            
            context.beginPDFPage(nil)
            
            // 1. Draw the original image
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.draw(cgImage, in: mediaBox)
            }
            
            // 2. Draw invisible text over bounding boxes
            context.setTextDrawingMode(.invisible)
            
            for block in textBlocks {
                // Convert normalized rect (0-1) to PDF coordinates
                // Vision/Gemini bbox origin is usually Top-Left, PDF is Bottom-Left
                // But our TextBlock struct likely has normalized coordinates (0-1)
                
                let pdfRect = CGRect(
                    x: block.boundingBox.origin.x * image.size.width,
                    y: (1.0 - block.boundingBox.origin.y - block.boundingBox.height) * image.size.height, // Flip Y
                    width: block.boundingBox.width * image.size.width,
                    height: block.boundingBox.height * image.size.height
                )
                
                // Calculate font size to fit height
                let fontSize = pdfRect.height * 0.8 // Heuristic
                
                // Draw text
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.clear // Double ensure invisibility
                ]
                
                let attributedString = NSAttributedString(string: block.text, attributes: attributes)
                
                // Draw text in the calculated rect
                // Note: This is a simplification. Precise text positioning requires more complex layout logic.
                // But for "searchable PDF" purposes, this overlay is usually sufficient.
                let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
                let path = CGPath(rect: pdfRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), path, nil)
                CTFrameDraw(frame, context)
            }
            
            context.endPDFPage()
            context.closePDF()
            
            do {
                try pdfData.write(to: url)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    // Legacy text-only PDF export (fallback)
    func exportAsTextPDF(content: String, filename: String, metadata: OCRMetadata? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // Create attributed string
            let font = NSFont.systemFont(ofSize: 12)
            let titleFont = NSFont.boldSystemFont(ofSize: 14)
            
            let attributedString = NSMutableAttributedString()
            
            // Add metadata header
            if let meta = metadata {
                let header = NSMutableAttributedString()
                header.append(NSAttributedString(string: "OCR Result\n\n", attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 18)
                ]))
                header.append(NSAttributedString(string: "Engine: \(meta.engine)\n", attributes: [.font: font]))
                header.append(NSAttributedString(string: "Confidence: \(meta.confidenceString)\n", attributes: [.font: font]))
                if let lang = meta.language {
                    header.append(NSAttributedString(string: "Language: \(lang)\n", attributes: [.font: font]))
                }
                header.append(NSAttributedString(string: "Date: \(self.formatDate(meta.timestamp))\n\n", attributes: [.font: font]))
                header.append(NSAttributedString(string: "Content:\n\n", attributes: [.font: titleFont]))
                
                attributedString.append(header)
            }
            
            // Add content
            attributedString.append(NSAttributedString(string: content, attributes: [.font: font]))
            
            // Create PDF
            let pdfData = NSMutableData()
            let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
            
            var pageSize = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
            guard let context = CGContext(consumer: consumer, mediaBox: &pageSize, nil) else { return }
            
            context.beginPDFPage(nil)
            
            let textRect = CGRect(x: 50, y: 50, width: 512, height: 692)
            attributedString.draw(in: textRect)
            
            context.endPDFPage()
            context.closePDF()
            
            do {
                try pdfData.write(to: url)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func generateFilename(filename: String, engine: String, pageIndex: Int, ext: String) -> String {
        // Format: {filename}_{ocr model}_{01}.ext
        let indexString = String(format: "%02d", pageIndex + 1)
        return "\(filename)_\(engine)_\(indexString).\(ext)"
    }
}
