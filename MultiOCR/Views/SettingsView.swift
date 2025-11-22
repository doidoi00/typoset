//
//  SettingsView.swift
//  MultiOCR
//
//  SwiftUI settings window
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            APIKeysSettingsView()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }
                .tag(1)
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(2)
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @State private var defaultEngine: OCREngineType
    @State private var autoCopy: Bool
    
    init() {
        _defaultEngine = State(initialValue: SettingsManager.shared.defaultEngine)
        _autoCopy = State(initialValue: SettingsManager.shared.autoCopyToClipboard)
    }
    
    var body: some View {
        Form {
            Section {
                Picker("Default OCR Engine:", selection: $defaultEngine) {
                    ForEach(OCREngineType.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .onChange(of: defaultEngine) { _, newValue in
                    SettingsManager.shared.defaultEngine = newValue
                }
                
                Toggle("Auto-copy to clipboard", isOn: $autoCopy)
                    .onChange(of: autoCopy) { _, newValue in
                        SettingsManager.shared.autoCopyToClipboard = newValue
                    }
            } header: {
                Text("General")
                    .font(.headline)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About MultiOCR")
                        .font(.headline)
                    Text("A powerful OCR app supporting multiple AI engines")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - API Keys Settings

struct APIKeysSettingsView: View {
    @State private var geminiKey: String = ""
    @State private var openAIKey: String = ""
    @State private var mistralKey: String = ""
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini API Key")
                        .font(.headline)
                    SecureField("Enter your Gemini API key", text: $geminiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: geminiKey) { _, newValue in
                            SettingsManager.shared.geminiAPIKey = newValue
                        }
                    Link("Get API key from Google AI Studio", destination: URL(string: "https://makersuite.google.com/app/apikey")!)
                        .font(.caption)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI API Key")
                        .font(.headline)
                    SecureField("Enter your OpenAI API key", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openAIKey) { _, newValue in
                            SettingsManager.shared.openAIAPIKey = newValue
                        }
                    Link("Get API key from OpenAI Platform", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mistral API Key")
                        .font(.headline)
                    SecureField("Enter your Mistral API key", text: $mistralKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: mistralKey) { _, newValue in
                            SettingsManager.shared.mistralAPIKey = newValue
                        }
                    Link("Get API key from Mistral Console", destination: URL(string: "https://console.mistral.ai/api-keys/")!)
                        .font(.caption)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("API keys are stored securely in your macOS Keychain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadKeys()
        }
    }
    
    private func loadKeys() async {
        // Load keys in background to avoid blocking main thread with Keychain access
        let gemini = await Task.detached { SettingsManager.shared.geminiAPIKey ?? "" }.value
        let openAI = await Task.detached { SettingsManager.shared.openAIAPIKey ?? "" }.value
        let mistral = await Task.detached { SettingsManager.shared.mistralAPIKey ?? "" }.value
        
        await MainActor.run {
            self.geminiKey = gemini
            self.openAIKey = openAI
            self.mistralKey = mistral
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Capture with default engine:")
                    Spacer()
                    Text("⌘⇧1")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text("Show quick capture menu:")
                    Spacer()
                    Text("⌘⇧2")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            } header: {
                Text("Keyboard Shortcuts")
                    .font(.headline)
            }
            
            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Keyboard shortcuts work globally, even when the app is in the background")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
