import Foundation
import Combine
import AppKit

struct APIStatus {
    let isSuccess: Bool
    let message: String
}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var geminiKey: String = ""
    @Published var openAIKey: String = ""
    @Published var mistralKey: String = ""
    
    @Published var geminiTesting = false
    @Published var openAITesting = false
    @Published var mistralTesting = false
    
    @Published var geminiStatus: APIStatus?
    @Published var openAIStatus: APIStatus?
    @Published var mistralStatus: APIStatus?
    
    @Published var geminiModels: [String] = []
    @Published var selectedGeminiModel: String = "gemini-2.5-flash-lite" { didSet { save("selected_gemini_model", selectedGeminiModel) } }
    
    @Published var openAIModels: [String] = []
    @Published var selectedOpenAIModel: String = "gpt-5-mini" { didSet { save("selectedOpenAIModel", selectedOpenAIModel) } }
    
    @Published var mistralModels: [String] = []
    @Published var selectedMistralModel: String = "mistral-ocr-latest" { didSet { save("selectedMistralModel", selectedMistralModel) } }
    
    @Published var geminiCLIPath: String = "/usr/local/bin/gemini" { didSet { save("geminiCLIPath", geminiCLIPath) } }
    
    @Published var customOCRPrompt: String = DefaultPrompts.standard { didSet { save("customOCRPrompt", customOCRPrompt) } }
    
    // MARK: - General Settings
    @Published var showDockIcon: Bool = true { didSet { save("showDockIcon", showDockIcon); updateAppVisibility() } }
    @Published var startAtLogin: Bool = false { didSet { save("startAtLogin", startAtLogin) } }
    @Published var playCaptureSound: Bool = true { didSet { save("playCaptureSound", playCaptureSound) } }
    @Published var showNotifications: Bool = true { didSet { save("showNotifications", showNotifications) } }
    
    // MARK: - OCR Defaults
    @Published var defaultEngine: String = "Apple Vision" { didSet { save("defaultEngine", defaultEngine) } }
    @Published var defaultLanguage: String = "Auto" { didSet { save("defaultLanguage", defaultLanguage) } }
    @Published var imageOptimizationLevel: String = "Medium" { didSet { save("imageOptimizationLevel", imageOptimizationLevel) } }
    
    // MARK: - Shortcuts & Capture
    @Published var captureShortcut: String = "⌘F1" { didSet { save("captureShortcut", captureShortcut) } }
    @Published var captureMultiShortcut: String = "⌘F2" { didSet { save("captureMultiShortcut", captureMultiShortcut) } }
    @Published var importShortcut: String = "⌘O" { didSet { save("importShortcut", importShortcut) } }
    
    @Published var saveScreenshots: Bool = false { didSet { save("saveScreenshots", saveScreenshots) } }
    @Published var screenshotSaveDirectory: String = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "" { didSet { save("screenshotSaveDirectory", screenshotSaveDirectory) } }
    @Published var hideWindowOnCapture: Bool = false { didSet { save("hideWindowOnCapture", hideWindowOnCapture) } }
    
    // MARK: - Output & History
    @Published var autoCopyToClipboard: Bool = true { didSet { save("autoCopyToClipboard", autoCopyToClipboard) } }
    @Published var cumulateClipboard: Bool = false { didSet { save("cumulateClipboard", cumulateClipboard) } }
    @Published var historyRetentionDays: Int = 30 { didSet { save("historyRetentionDays", historyRetentionDays) } }
    @Published var defaultExportFormat: String = "txt" { didSet { save("defaultExportFormat", defaultExportFormat) } }
    
    // MARK: - Token Usage
    @Published var geminiUsage: Int = 0 { didSet { save("geminiUsage", geminiUsage) } }
    @Published var openAIUsage: Int = 0 { didSet { save("openAIUsage", openAIUsage) } }
    @Published var mistralUsage: Int = 0 { didSet { save("mistralUsage", mistralUsage) } }
    
    private let keychain = KeychainService.shared
    private let defaults = UserDefaults.standard
    
    static let shared = SettingsViewModel()
    
    init() {
        loadKeys()
        loadSelectedModels()
        loadSettings()
    }
    
    private func loadSettings() {
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        startAtLogin = defaults.bool(forKey: "startAtLogin")
        playCaptureSound = defaults.object(forKey: "playCaptureSound") as? Bool ?? true
        showNotifications = defaults.object(forKey: "showNotifications") as? Bool ?? true
        
        defaultEngine = defaults.string(forKey: "defaultEngine") ?? "Apple Vision"
        defaultLanguage = defaults.string(forKey: "defaultLanguage") ?? "Auto"
        imageOptimizationLevel = defaults.string(forKey: "imageOptimizationLevel") ?? "Medium"
        
        captureShortcut = defaults.string(forKey: "captureShortcut") ?? "⌘F1"
        captureMultiShortcut = defaults.string(forKey: "captureMultiShortcut") ?? "⌘F2"
        importShortcut = defaults.string(forKey: "importShortcut") ?? "⌘O"
        
        saveScreenshots = defaults.bool(forKey: "saveScreenshots")
        screenshotSaveDirectory = defaults.string(forKey: "screenshotSaveDirectory") ?? (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "")
        hideWindowOnCapture = defaults.bool(forKey: "hideWindowOnCapture")
        
        autoCopyToClipboard = defaults.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        cumulateClipboard = defaults.bool(forKey: "cumulateClipboard")
        historyRetentionDays = defaults.integer(forKey: "historyRetentionDays") == 0 ? 30 : defaults.integer(forKey: "historyRetentionDays")
        defaultExportFormat = defaults.string(forKey: "defaultExportFormat") ?? "txt"
        
        geminiUsage = defaults.integer(forKey: "geminiUsage")
        openAIUsage = defaults.integer(forKey: "openAIUsage")
        mistralUsage = defaults.integer(forKey: "mistralUsage")
        
        customOCRPrompt = defaults.string(forKey: "customOCRPrompt") ?? DefaultPrompts.standard
    }
    
    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }
    
    func incrementUsage(for engine: String, tokens: Int) {
        switch engine {
        case "Gemini":
            self.geminiUsage += tokens
        case "GPT":
            self.openAIUsage += tokens
        case "Mistral":
            self.mistralUsage += tokens
        default:
            break
        }
    }
    
    private func updateAppVisibility() {
        if showDockIcon {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    private func fetchGeminiModels(apiKey: String) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.geminiTesting = false
                if let error = error {
                    self?.geminiStatus = APIStatus(isSuccess: false, message: error.localizedDescription)
                    return
                }
                
                guard let data = data else {
                    self?.geminiStatus = APIStatus(isSuccess: false, message: "No data received")
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
                    // Filter for models that support generateContent
                    self?.geminiModels = response.models
                        .filter { $0.supportedGenerationMethods.contains("generateContent") }
                        .map { $0.name.replacingOccurrences(of: "models/", with: "") }
                        .sorted()
                    
                    if let models = self?.geminiModels, !models.isEmpty, let current = self?.selectedGeminiModel, current.isEmpty {
                        if models.contains("gemini-2.5-flash-lite") {
                            self?.selectedGeminiModel = "gemini-2.5-flash-lite"
                        } else {
                            self?.selectedGeminiModel = models.first ?? ""
                        }
                    }
                    
                    self?.geminiStatus = APIStatus(isSuccess: true, message: "Connected")
                } catch {
                    self?.geminiStatus = APIStatus(isSuccess: false, message: "Failed to parse models")
                }
            }
        }.resume()
    }
    
    private func fetchOpenAIModels(apiKey: String) {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.openAITesting = false
                if let error = error {
                    self?.openAIStatus = APIStatus(isSuccess: false, message: error.localizedDescription)
                    return
                }
                
                guard let data = data else {
                    self?.openAIStatus = APIStatus(isSuccess: false, message: "No data received")
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
                    self?.openAIModels = response.data
                        .map { $0.id }
                        .filter { $0.contains("gpt") } // Filter for GPT models
                        .sorted()
                    
                    if let models = self?.openAIModels, !models.isEmpty, let current = self?.selectedOpenAIModel, !models.contains(current) {
                        self?.selectedOpenAIModel = models.first ?? "gpt-5-mini"
                    }
                    
                    self?.openAIStatus = APIStatus(isSuccess: true, message: "Connected")
                } catch {
                    self?.openAIStatus = APIStatus(isSuccess: false, message: "Failed to parse models")
                }
            }
        }.resume()
    }
    
    private func fetchMistralModels(apiKey: String) {
        guard let url = URL(string: "https://api.mistral.ai/v1/models") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.mistralTesting = false
                if let error = error {
                    self?.mistralStatus = APIStatus(isSuccess: false, message: error.localizedDescription)
                    return
                }
                
                guard let data = data else {
                    self?.mistralStatus = APIStatus(isSuccess: false, message: "No data received")
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(MistralModelsResponse.self, from: data)
                    self?.mistralModels = response.data
                        .map { $0.id }
                        .sorted()
                    
                    if let models = self?.mistralModels, !models.isEmpty, let current = self?.selectedMistralModel, !models.contains(current) {
                        self?.selectedMistralModel = models.first ?? "mistral-ocr-latest"
                    }
                    
                    self?.mistralStatus = APIStatus(isSuccess: true, message: "Connected")
                } catch {
                    self?.mistralStatus = APIStatus(isSuccess: false, message: "Failed to parse models")
                }
            }
        }.resume()
    }
    
    private func loadKeys() {
        let keys = keychain.loadAllKeys()
        
        geminiKey = keys.gemini ?? ""
        if !geminiKey.isEmpty { fetchGeminiModels(apiKey: geminiKey) }
        
        openAIKey = keys.openai ?? ""
        if !openAIKey.isEmpty { fetchOpenAIModels(apiKey: openAIKey) }
        
        mistralKey = keys.mistral ?? ""
        if !mistralKey.isEmpty { fetchMistralModels(apiKey: mistralKey) }
    }
    
    private func loadSelectedModels() {
        selectedGeminiModel = defaults.string(forKey: "selected_gemini_model") ?? "gemini-2.5-flash-lite"
        selectedOpenAIModel = defaults.string(forKey: "selectedOpenAIModel") ?? "gpt-5-mini"
        selectedMistralModel = defaults.string(forKey: "selectedMistralModel") ?? "mistral-ocr-latest"
        
        geminiCLIPath = defaults.string(forKey: "geminiCLIPath") ?? "/usr/local/bin/gemini"
        
        customOCRPrompt = defaults.string(forKey: "customOCRPrompt") ?? DefaultPrompts.standard
    }
    
    func saveGeminiKey() {
        saveAllKeys()
        fetchGeminiModels(apiKey: geminiKey)
    }
    
    func saveOpenAIKey() {
        saveAllKeys()
        fetchOpenAIModels(apiKey: openAIKey)
    }
    
    func saveMistralKey() {
        saveAllKeys()
        fetchMistralModels(apiKey: mistralKey)
    }
    
    private func saveAllKeys() {
        let keys = KeychainService.APIKeys(
            gemini: geminiKey.isEmpty ? nil : geminiKey,
            openai: openAIKey.isEmpty ? nil : openAIKey,
            mistral: mistralKey.isEmpty ? nil : mistralKey
        )
        try? keychain.saveAllKeys(keys)
    }
    
    func testGeminiConnection() {
        geminiTesting = true
        geminiStatus = nil
        
        Task {
            do {
                let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(geminiKey)"
                guard let url = URL(string: urlString) else {
                    DispatchQueue.main.async {
                        self.geminiTesting = false
                        self.geminiStatus = APIStatus(isSuccess: false, message: "✗ Invalid URL")
                    }
                    return
                }
                
                let (data, response) = try await URLSession.shared.data(from: url)
                
                if let httpResponse = response as? HTTPURLResponse {
                    DispatchQueue.main.async {
                        self.geminiTesting = false
                        if httpResponse.statusCode == 200 {
                            // Attempt to decode to confirm it's a valid response structure
                            if (try? JSONDecoder().decode(GeminiModelsResponse.self, from: data)) != nil {
                                self.geminiStatus = APIStatus(isSuccess: true, message: "✓ Connected")
                            } else {
                                self.geminiStatus = APIStatus(isSuccess: false, message: "✗ Invalid response format")
                            }
                        } else {
                            self.geminiStatus = APIStatus(isSuccess: false, message: "✗ Invalid API Key (\(httpResponse.statusCode))")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.geminiTesting = false
                    self.geminiStatus = APIStatus(isSuccess: false, message: "✗ Connection Failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func testOpenAIConnection() {
        openAITesting = true
        openAIStatus = nil
        
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    DispatchQueue.main.async {
                        self.openAITesting = false
                        if httpResponse.statusCode == 200 {
                            self.openAIStatus = APIStatus(isSuccess: true, message: "✓ Connected")
                        } else {
                            self.openAIStatus = APIStatus(isSuccess: false, message: "✗ Invalid API Key")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.openAITesting = false
                    self.openAIStatus = APIStatus(isSuccess: false, message: "✗ Connection Failed")
                }
            }
        }
    }
    
    func testMistralConnection() {
        mistralTesting = true
        mistralStatus = nil
        
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/models")!)
                request.setValue("Bearer \(mistralKey)", forHTTPHeaderField: "Authorization")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    DispatchQueue.main.async {
                        self.mistralTesting = false
                        if httpResponse.statusCode == 200 {
                            self.mistralStatus = APIStatus(isSuccess: true, message: "✓ Connected")
                        } else {
                            self.mistralStatus = APIStatus(isSuccess: false, message: "✗ Invalid API Key")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.mistralTesting = false
                    self.mistralStatus = APIStatus(isSuccess: false, message: "✗ Connection Failed")
                }
            }
        }
    }
}

// Gemini Models Response
struct GeminiModelsResponse: Codable {
    let models: [GeminiModelInfo]
}

struct GeminiModelInfo: Codable {
    let name: String
    let supportedGenerationMethods: [String]
}

struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModelInfo]
}

struct OpenAIModelInfo: Codable {
    let id: String
}

struct MistralModelsResponse: Codable {
    let data: [MistralModelInfo]
}

struct MistralModelInfo: Codable {
    let id: String
}
