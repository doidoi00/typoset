import Foundation
import AppKit

class FavoritesManager {
    static let shared = FavoritesManager()
    
    private let userDefaults = UserDefaults.standard
    private let favoritesKey = "favorites"
    
    func add(text: String, image: NSImage?) {
        var favorites = fetchAll()
        let newItem = FavoriteItem(
            id: UUID(),
            text: text,
            date: Date(),
            imagePath: saveImage(image)
        )
        favorites.insert(newItem, at: 0)
        save(favorites)
    }
    
    func remove(id: UUID) {
        var favorites = fetchAll()
        favorites.removeAll { $0.id == id }
        save(favorites)
    }
    
    func fetchAll() -> [FavoriteItem] {
        guard let data = userDefaults.data(forKey: favoritesKey),
              let items = try? JSONDecoder().decode([FavoriteItem].self, from: data) else {
            return []
        }
        return items
    }
    
    private func save(_ favorites: [FavoriteItem]) {
        if let data = try? JSONEncoder().encode(favorites) {
            userDefaults.set(data, forKey: favoritesKey)
        }
    }
    
    private func saveImage(_ image: NSImage?) -> String? {
        guard let image = image,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            return nil
        }
        
        let path = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true
        ).first!
        let dirUrl = URL(fileURLWithPath: path).appendingPathComponent("com.doidoi00.MultiOCR/Favorites")
        try? FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true)
        
        let fileUrl = dirUrl.appendingPathComponent("\(UUID().uuidString).jpg")
        try? jpegData.write(to: fileUrl)
        return fileUrl.path
    }
}

struct FavoriteItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let date: Date
    let imagePath: String?
    
    var image: NSImage? {
        guard let path = imagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }
}
