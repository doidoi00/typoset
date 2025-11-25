import Foundation
import AppKit
import SQLite

class DatabaseService {
    static let shared = DatabaseService()
    
    private var db: Connection?
    private let history = Table("history")
    
    // Columns
    private let id = Expression<String>("id")
    private let text = Expression<String>("text")
    private let date = Expression<Date>("date")
    private let engine = Expression<String>("engine")
    private let imagePath = Expression<String?>("image_path")
    private let source = Expression<String>("source") // "capture", "pdf", or "image"
    private let fileId = Expression<String>("file_id") // Groups multiple OCR results from same file
    private let pageIndex = Expression<Int>("page_index") // Page number for PDFs (0-indexed)
    private let originalFilePath = Expression<String?>("original_file_path") // Path to original file before OCR
    
    private init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let path = NSSearchPathForDirectoriesInDomains(
                .applicationSupportDirectory, .userDomainMask, true
            ).first!
            
            let dirUrl = URL(fileURLWithPath: path).appendingPathComponent("com.doidoi00.MultiOCR")
            try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true)
            
            let dbPath = dirUrl.appendingPathComponent("db.sqlite3").path
            db = try Connection(dbPath)
            
            try db?.run(history.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(text)
                t.column(date)
                t.column(engine)
                t.column(imagePath)
                t.column(source, defaultValue: "capture")
                t.column(fileId, defaultValue: "")
                t.column(pageIndex, defaultValue: 0)
                t.column(originalFilePath)
            })
            
            // Migration: Add columns if they don't exist
            if let db = db {
                // Migration for 'source' column
                do {
                    try db.run(history.addColumn(source, defaultValue: "capture"))
                } catch {}
                
                // Migration for 'fileId' column
                do {
                    try db.run(history.addColumn(fileId, defaultValue: ""))
                } catch {}

                // Migration: Add pageIndex column if it doesn't exist
                let hasPageIndex = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('history') WHERE name='page_index'") as! Int64
                if hasPageIndex == 0 {
                    try db.run("ALTER TABLE history ADD COLUMN page_index INTEGER DEFAULT 0")
                }
                
                // Migration: Add originalFilePath column if it doesn't exist
                let hasOriginalFilePath = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('history') WHERE name='original_file_path'") as! Int64
                if hasOriginalFilePath == 0 {
                    try db.run("ALTER TABLE history ADD COLUMN original_file_path TEXT")
                }
            }
        } catch {
            print("Database setup failed: \(error)")
        }
    }
    
    func save(result: OCRResult, image: NSImage?, source: String, fileId: String, pageIndex: Int = 0, originalFilePath: String? = nil) {
        do {
            var savedImagePath: String? = nil
            if let image = image {
                savedImagePath = saveImageToDisk(image, id: result.id.uuidString)
            }
            
            try db?.run(history.insert(
                id <- result.id.uuidString,
                text <- result.text,
                date <- Date(),
                engine <- result.engine,
                imagePath <- savedImagePath,
                self.source <- source,
                self.fileId <- fileId,
                self.pageIndex <- pageIndex,
                self.originalFilePath <- originalFilePath
            ))
        } catch {
            print("Insert failed: \(error)")
        }
    }
    
    func fetchHistory() -> [HistoryItem] {
        var items: [HistoryItem] = []
        do {
            guard let db = db else { return [] }
            for row in try db.prepare(history.order(date.desc)) {
                items.append(HistoryItem(
                    id: UUID(uuidString: row[id]) ?? UUID(),
                    text: row[text],
                    date: row[date],
                    engine: row[engine],
                    imagePath: row[imagePath],
                    source: row[source],
                    fileId: row[fileId],
                    pageIndex: row[pageIndex],
                    originalFilePath: row[originalFilePath]
                ))
            }
        } catch {
            print("Fetch failed: \(error)")
        }
        return items
    }
    
    func fetchGroupedHistory() -> [FileGroup] {
        let items = fetchHistory()
        let grouped = Dictionary(grouping: items) { $0.fileId }
        
        return grouped.compactMap { (fileId, items) -> FileGroup? in
            guard let firstItem = items.first else { return nil }
            return FileGroup(
                fileId: fileId,
                source: firstItem.source,
                date: items.map { $0.date }.max() ?? firstItem.date,
                imagePath: firstItem.imagePath,
                originalFilePath: firstItem.originalFilePath,
                items: items.sorted { $0.pageIndex < $1.pageIndex } // Sort by page order
            )
        }.sorted { $0.date > $1.date }
    }
    
    func fetchPages(fileId providedFileId: String) -> [HistoryItem] {
        var items: [HistoryItem] = []
        do {
            guard let db = db else { return [] }
            let query = history.filter(self.fileId == providedFileId).order(pageIndex.asc)
            for row in try db.prepare(query) {
                items.append(HistoryItem(
                    id: UUID(uuidString: row[id]) ?? UUID(),
                    text: row[text],
                    date: row[date],
                    engine: row[engine],
                    imagePath: row[imagePath],
                    source: row[source],
                    fileId: row[self.fileId],
                    pageIndex: row[self.pageIndex],
                    originalFilePath: row[self.originalFilePath]
                ))
            }
        } catch {
            print("Fetch pages failed: \(error)")
        }
        return items
    }
    
    private func saveImageToDisk(_ image: NSImage, id: String) -> String? {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else { return nil }
        
        do {
            let path = NSSearchPathForDirectoriesInDomains(
                .applicationSupportDirectory, .userDomainMask, true
            ).first!
            let dirUrl = URL(fileURLWithPath: path).appendingPathComponent("com.doidoi00.MultiOCR/Images")
            try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true)
            
            let fileUrl = dirUrl.appendingPathComponent("\(id).jpg")
            try jpegData.write(to: fileUrl)
            return fileUrl.path
        } catch {
            print("Image save failed: \(error)")
            return nil
        }
    }
}

struct HistoryItem: Identifiable {
    let id: UUID
    let text: String
    let date: Date
    let engine: String
    let imagePath: String?
    let source: String
    let fileId: String
    let pageIndex: Int
    let originalFilePath: String?
    
    var image: NSImage? {
        guard let path = imagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }
}

struct FileGroup: Identifiable {
    let fileId: String
    let source: String
    let date: Date
    let imagePath: String?
    let originalFilePath: String?
    let items: [HistoryItem]
    
    var id: String { fileId }
    
    var image: NSImage? {
        guard let path = imagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }
    
    var combinedText: String {
        items.map { $0.text }.joined(separator: "\n\n---\n\n")
    }
}
