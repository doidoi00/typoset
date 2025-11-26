import SwiftUI
import Combine
import AppKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
class MainViewModel: ObservableObject {
    @Published var currentImage: NSImage?
    @Published var recognizedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var selectedEngine: String = "Apple Vision" {
        didSet {
            ocrManager.setEngine(named: selectedEngine)
            
            // Auto-reprocess current image when engine changes
            if let image = currentImage {
                Task {
                    let source: String
                    if pdfDocument != nil {
                        source = "pdf"
                    } else if currentOriginalFilePath != nil {
                        source = "image"
                    } else {
                        source = "capture"
                    }
                    await processImage(image, source: source)
                }
            }
        }
    }
    
    // PDF State
    @Published var pdfDocument: PDFDocument?
    @Published var currentPageIndex: Int = 0
    @Published var totalPages: Int = 0
    
    // Current file ID for grouping OCR results
    private var currentFileId: String = UUID().uuidString
    
    // Original file path (for PDF/image imports)
    private var currentOriginalFilePath: String?
    
    // Store for Export
    @Published var currentFilename: String = "Capture"
    @Published var lastOCRResult: OCRResult?
    
    // OCR Cache: fileId -> [pageIndex: text]
    private var ocrCache: [String: [Int: String]] = [:]
    
    private let ocrManager = OCRManager.shared
    private let captureManager = ScreenCaptureManager.shared
    
    func captureScreen() {
        currentFileId = UUID().uuidString // New file group for each capture
        currentOriginalFilePath = nil // No original file for captures
        currentFilename = "Capture"
        captureManager.startCapture { [weak self] image in
            DispatchQueue.main.async {
                self?.pdfDocument = nil // Clear PDF state
                self?.currentImage = image
                Task {
                    await self?.processImage(image, source: "capture")
                }
            }
        }
    }
    
    func processImage(_ image: NSImage, source: String = "capture", pageIndex: Int = 0) async {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.recognizedText = "Processing..."
        }
        
        do {
            let result = try await ocrManager.performOCR(on: image)
            
            // Save to History with fileId, pageIndex, and originalFilePath
            DatabaseService.shared.save(
                result: result, 
                image: image, 
                source: source, 
                fileId: currentFileId, 
                pageIndex: pageIndex,
                originalFilePath: currentOriginalFilePath
            )
            
            // --- Defensive text processing ---
            let rawText = result.text
            var finalText = rawText
            
            // Check if the text looks like a JSON array from our AI engines
            if rawText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                struct TempRegion: Decodable { let text: String? }
                if let jsonData = rawText.data(using: .utf8) {
                    do {
                        let regions = try JSONDecoder().decode([TempRegion].self, from: jsonData)
                        let extractedTexts = regions.compactMap { $0.text }.filter { !$0.isEmpty }
                        if !extractedTexts.isEmpty {
                            finalText = extractedTexts.joined(separator: "\n")
                        }
                    } catch {
                        // Not the JSON we expected, or malformed. Fallback to rawText.
                        print("Attempted to parse result as JSON but failed: \(error.localizedDescription)")
                    }
                }
            }

            // Cache the final processed text
            if ocrCache[currentFileId] == nil {
                ocrCache[currentFileId] = [:]
            }
            ocrCache[currentFileId]?[pageIndex] = finalText
            
            DispatchQueue.main.async {
                self.recognizedText = finalText
                self.lastOCRResult = result
                self.isProcessing = false
            }
        } catch {
            DispatchQueue.main.async {
                self.recognizedText = "Error: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }
    
    // Track open panel to prevent duplicates
    private var openPanel: NSOpenPanel?
    
    func importFile(allowedTypes: [UTType] = [.image, .pdf]) {
        // If a panel is already open, just bring it to front
        if let existingPanel = openPanel, existingPanel.isVisible {
            existingPanel.makeKeyAndOrderFront(nil)
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        // Find and make the main window key
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.level == .normal }) {
            window.makeKeyAndOrderFront(nil)
        }
        
        // Small delay to ensure window is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = allowedTypes
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            
            // Store reference to prevent duplicates
            self?.openPanel = panel
            
            panel.begin { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.handleFile(at: url)
                }
                // Clear reference when done
                self?.openPanel = nil
            }
        }
    }
    
    // Call this when app is terminating to clean up
    func cleanup() {
        openPanel?.close()
        openPanel = nil
    }
    
    private func handleFile(at url: URL) {
        currentFileId = UUID().uuidString // New file group for each imported file
        currentOriginalFilePath = url.path // Store original file path
        currentFilename = url.deletingPathExtension().lastPathComponent
        
        if url.pathExtension.lowercased() == "pdf" {
            if let document = PDFDocument(url: url) {
                self.pdfDocument = document
                self.totalPages = document.pageCount
                self.currentPageIndex = 0
                self.loadCurrentPDFPage()
            }
        } else {
            if let image = NSImage(contentsOf: url) {
                self.pdfDocument = nil
                self.currentImage = image
                Task {
                    await self.processImage(image, source: "image")
                }
            }
        }
    }
    
    func loadCurrentPDFPage() {
        guard let document = pdfDocument,
              let page = document.page(at: currentPageIndex) else { return }
        
        // Check cache first
        if let cachedText = ocrCache[currentFileId]?[currentPageIndex] {
            let pageRect = page.bounds(for: .mediaBox)
            let image = NSImage(size: pageRect.size, flipped: false) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.setFillColor(NSColor.white.cgColor)
                context.fill(rect)
                page.draw(with: .mediaBox, to: context)
                return true
            }
            
            self.currentImage = image
            self.recognizedText = cachedText
            self.isProcessing = false
            return
        }
        
        // Not cached - render and OCR
        let pageRect = page.bounds(for: .mediaBox)
        let image = NSImage(size: pageRect.size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        
        self.currentImage = image
        Task {
            await self.processImage(image, source: "pdf", pageIndex: currentPageIndex)
        }
    }
    
    func nextPage() {
        guard currentPageIndex < totalPages - 1 else { return }
        currentPageIndex += 1
        loadCurrentPDFPage()
    }
    
    func previousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        loadCurrentPDFPage()
    }
    
    func goToPage(_ index: Int) {
        guard index >= 0 && index < totalPages else { return }
        currentPageIndex = index
        loadCurrentPDFPage()
    }
    
    // Re-process current page with current engine (clears cache)
    func reprocessCurrentPage() {
        guard let image = currentImage else { return }
        
        // Clear cache for current page
        ocrCache[currentFileId]?[currentPageIndex] = nil
        
        // Determine source type
        let source = pdfDocument != nil ? "pdf" : (currentFilename == "Capture" ? "capture" : "image")
        
        // Reprocess with current engine
        Task {
            await processImage(image, source: source, pageIndex: currentPageIndex)
        }
    }

    
    private func renderPDFPageToImage(url: URL) -> NSImage? {
        // Deprecated in favor of stateful handling, keeping for reference or removing if unused
        return nil 
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(recognizedText, forType: .string)
    }
    
    // Load file group from history
    func loadFileGroup(_ group: FileGroup) {
        currentFileId = group.fileId
        currentFilename = group.items.first?.text.prefix(20).description ?? "History"
        
        // Fetch all pages for this fileId
        let pages = DatabaseService.shared.fetchPages(fileId: group.fileId)
        
        // Pre-populate cache
        ocrCache[group.fileId] = [:]
        for page in pages {
            ocrCache[group.fileId]?[page.pageIndex] = page.text
        }
        
        // Try to load original file if available
        if let originalPath = group.originalFilePath,
           FileManager.default.fileExists(atPath: originalPath) {
            let url = URL(fileURLWithPath: originalPath)
            currentOriginalFilePath = originalPath
            
            // Check if it's a PDF
            if url.pathExtension.lowercased() == "pdf" {
                if let document = PDFDocument(url: url) {
                    // Restore PDF document
                    self.pdfDocument = document
                    self.totalPages = document.pageCount
                    self.currentPageIndex = 0
                    
                    // Load first page
                    if let page = document.page(at: 0) {
                        let pageRect = page.bounds(for: .mediaBox)
                        let image = NSImage(size: pageRect.size, flipped: false) { rect in
                            guard let context = NSGraphicsContext.current?.cgContext else { return false }
                            context.setFillColor(NSColor.white.cgColor)
                            context.fill(rect)
                            page.draw(with: .mediaBox, to: context)
                            return true
                        }
                        self.currentImage = image
                    }
                    
                    // Show cached text for first page
                    if let firstPageText = ocrCache[group.fileId]?[0] {
                        recognizedText = firstPageText
                    }
                    return
                }
            } else {
                // Load original image
                if let image = NSImage(contentsOf: url) {
                    self.pdfDocument = nil
                    self.currentImage = image
                    
                    // Show cached text
                    if let cachedText = ocrCache[group.fileId]?[0] {
                        recognizedText = cachedText
                    }
                    return
                }
            }
        }
        
        // Fallback: Use saved image if original file not available
        if let image = group.image {
            currentImage = image
        }
        pdfDocument = nil
        currentOriginalFilePath = nil
        
        // Show combined text
        recognizedText = pages.sorted { $0.pageIndex < $1.pageIndex }.map { $0.text }.joined(separator: "\n\n---\n\n")
    }
    
    // MARK: - Favorites handling
    var isCurrentItemFavorited: Bool {
        // Simple check based on text content; could be expanded to image comparison
        let favorites = FavoritesManager.shared.fetchAll()
        return favorites.contains(where: { $0.text == recognizedText })
    }
    
    func toggleFavorite() {
        if isCurrentItemFavorited {
            // Find the matching favorite and remove it
            let favorites = FavoritesManager.shared.fetchAll()
            if let item = favorites.first(where: { $0.text == recognizedText }) {
                FavoritesManager.shared.remove(id: item.id)
            }
        } else {
            FavoritesManager.shared.add(text: recognizedText, image: currentImage)
        }
    }

    func exportAsText() {
        let metadata = createMetadata()
        let filename = ExportService.shared.generateFilename(filename: currentFilename, engine: selectedEngine, pageIndex: currentPageIndex, ext: "txt")
        ExportService.shared.exportAsText(content: recognizedText, filename: filename, metadata: metadata)
    }
    
    func exportAsMarkdown() {
        let metadata = createMetadata()
        let filename = ExportService.shared.generateFilename(filename: currentFilename, engine: selectedEngine, pageIndex: currentPageIndex, ext: "md")
        ExportService.shared.exportAsMarkdown(content: recognizedText, filename: filename, metadata: metadata)
    }
    
    func exportAsJSON() {
        let metadata = createMetadata()
        let filename = ExportService.shared.generateFilename(filename: currentFilename, engine: selectedEngine, pageIndex: currentPageIndex, ext: "json")
        ExportService.shared.exportAsJSON(content: recognizedText, filename: filename, metadata: metadata, textBlocks: lastOCRResult?.textBlocks)
    }
    
    func exportAsPDF() {
        let metadata = createMetadata()
        let filename = ExportService.shared.generateFilename(filename: currentFilename, engine: selectedEngine, pageIndex: currentPageIndex, ext: "pdf")
        
        if let image = currentImage, let blocks = lastOCRResult?.textBlocks, !blocks.isEmpty {
            // Use searchable PDF if we have image and blocks
            ExportService.shared.exportAsSearchablePDF(image: image, textBlocks: blocks, filename: filename, metadata: metadata)
        } else {
            // Fallback to text-only PDF
            ExportService.shared.exportAsTextPDF(content: recognizedText, filename: filename, metadata: metadata)
        }
    }
    
    private func createMetadata() -> OCRMetadata {
        let source = pdfDocument != nil ? "pdf" : "capture"
        return OCRMetadata(
            engine: selectedEngine,
            confidence: nil,  // Would need to store from last OCR result
            language: nil,
            timestamp: Date(),
            source: source,
            pageCount: pdfDocument?.pageCount
        )
    }


}
