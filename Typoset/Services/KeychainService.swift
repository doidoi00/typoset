import Foundation
import KeychainAccess

class KeychainService {
    static let shared = KeychainService()
    private let keychain = Keychain(service: "com.doidoi00.MultiOCR")
    private let allKeysService = "com.doidoi00.MultiOCR.APIKeys"
    
    struct APIKeys: Codable {
        var gemini: String?
        var openai: String?
        var mistral: String?
    }
    
    // MARK: - Legacy Support
    
    func save(key: String, for service: String) throws {
        try keychain.set(key, key: service)
    }
    
    func load(for service: String) -> String? {
        try? keychain.get(service)
    }
    
    func delete(for service: String) throws {
        try keychain.remove(service)
    }
    
    // MARK: - Consolidated Support
    
    func saveAllKeys(_ keys: APIKeys) throws {
        let data = try JSONEncoder().encode(keys)
        if let jsonString = String(data: data, encoding: .utf8) {
            try keychain.set(jsonString, key: allKeysService)
        }
    }
    
    func loadAllKeys() -> APIKeys {
        // Try loading consolidated keys first
        if let jsonString = try? keychain.get(allKeysService),
           let data = jsonString.data(using: .utf8),
           let keys = try? JSONDecoder().decode(APIKeys.self, from: data) {
            return keys
        }
        
        // Fallback: Migrate legacy keys
        return migrateLegacyKeys()
    }
    
    private func migrateLegacyKeys() -> APIKeys {
        let gemini = load(for: "gemini_api_key")
        let openai = load(for: "openai_api_key")
        let mistral = load(for: "mistral_api_key")
        
        let keys = APIKeys(gemini: gemini, openai: openai, mistral: mistral)
        
        // Save to new consolidated storage if any key exists
        if gemini != nil || openai != nil || mistral != nil {
            try? saveAllKeys(keys)
            
            // Optional: Delete legacy keys after successful migration
            // Keeping them for now just in case, or we can delete them to clean up
             try? delete(for: "gemini_api_key")
             try? delete(for: "openai_api_key")
             try? delete(for: "mistral_api_key")
        }
        
        return keys
    }
}
