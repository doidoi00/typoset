import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var viewModel = SettingsViewModel.shared
    @State private var showGeminiKey = false
    @State private var showOpenAIKey = false
    @State private var showMistralKey = false
    
    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            ShortcutsSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Shortcuts & Capture", systemImage: "keyboard")
                }
            
            EnginesSettingsView(viewModel: viewModel, 
                                showGeminiKey: $showGeminiKey, 
                                showOpenAIKey: $showOpenAIKey, 
                                showMistralKey: $showMistralKey)
                .tabItem {
                    Label("Engines", systemImage: "cpu")
                }
            
            DataSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
        }
        .frame(width: 550, height: 450)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section("App Behavior") {
                Toggle("Show Dock Icon", isOn: $viewModel.showDockIcon)
                Toggle("Start at Login", isOn: $viewModel.startAtLogin)
                Toggle("Play Capture Sound", isOn: $viewModel.playCaptureSound)
                Toggle("Show Notifications", isOn: $viewModel.showNotifications)
            }
            
            Section("OCR Defaults") {
                Picker("Default Engine", selection: $viewModel.defaultEngine) {
                    Text("Apple Vision").tag("Apple Vision")
                    Text("Google Gemini").tag("Gemini")
                    Text("OpenAI GPT-4").tag("OpenAI")
                    Text("Mistral AI").tag("Mistral")
                }
                
                Picker("Default Language", selection: $viewModel.defaultLanguage) {
                    Text("Auto-Detect").tag("Auto")
                    Text("English").tag("en-US")
                    Text("Korean").tag("ko-KR")
                    Text("Japanese").tag("ja-JP")
                    Text("Chinese").tag("zh-CN")
                }
                
                Picker("Image Optimization", selection: $viewModel.imageOptimizationLevel) {
                    Text("Original (No Resize)").tag("Original")
                    Text("High (Max 2048px)").tag("High")
                    Text("Medium (Max 1024px)").tag("Medium")
                    Text("Low (Max 768px)").tag("Low")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section("Global Shortcuts") {
                HStack {
                    Text("Capture Region")
                    Spacer()
                    ShortcutField(text: $viewModel.captureShortcut)
                }
                
                HStack {
                    Text("Capture Multiple")
                    Spacer()
                    ShortcutField(text: $viewModel.captureMultiShortcut)
                }
                
                HStack {
                    Text("Import File")
                    Spacer()
                    ShortcutField(text: $viewModel.importShortcut)
                }
            }
            
            Section("Capture Behavior") {
                Toggle("Hide Window on Capture", isOn: $viewModel.hideWindowOnCapture)
                Toggle("Save Screenshots to File", isOn: $viewModel.saveScreenshots)
                
                if viewModel.saveScreenshots {
                    HStack {
                        Button("Select Folder") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK {
                                viewModel.screenshotSaveDirectory = panel.url?.path ?? ""
                            }
                        }
                        Text(viewModel.screenshotSaveDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Clipboard") {
                Toggle("Auto-copy OCR Result", isOn: $viewModel.autoCopyToClipboard)
                if viewModel.autoCopyToClipboard {
                    Toggle("Cumulate Multiple Results", isOn: $viewModel.cumulateClipboard)
                        .help("If enabled, new OCR results will be appended to the clipboard instead of replacing it.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct DataSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section("History") {
                Picker("Keep History For", selection: $viewModel.historyRetentionDays) {
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                    Text("90 Days").tag(90)
                    Text("Forever").tag(-1)
                }
                
                Button("Clear History Now", role: .destructive) {
                    // TODO: Implement clear history
                }
            }
            
            Section("Export Defaults") {
                Picker("Default Format", selection: $viewModel.defaultExportFormat) {
                    Text("Plain Text (.txt)").tag("txt")
                    Text("Markdown (.md)").tag("md")
                    Text("PDF (.pdf)").tag("pdf")
                    Text("JSON (.json)").tag("json")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutField: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .onTapGesture {
            // Placeholder for shortcut recorder
            // In a real app, this would open a key recorder
        }
    }
}

struct EnginesSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var showGeminiKey: Bool
    @Binding var showOpenAIKey: Bool
    @Binding var showMistralKey: Bool
    
    @State private var showAutoDetectAlert = false
    @State private var autoDetectedPath = ""
    @State private var showOpenPanel = false // Trigger for manual browse

    var body: some View {
        Form {
            Section(header: Text("Shared Prompt")) {
                VStack(alignment: .leading) {
                    Text("Custom OCR Prompt (Gemini / GPT / Gemini CLI)")
                        .font(.body)
                        .foregroundColor(.primary)
                    TextEditor(text: $viewModel.customOCRPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 150)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            }
            
            Section(header: Text("Google Gemini")) {
                HStack {
                    if showGeminiKey {
                        TextField("API Key", text: $viewModel.geminiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $viewModel.geminiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showGeminiKey.toggle() }) {
                        Image(systemName: showGeminiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showGeminiKey ? "Hide" : "Show")
                    
                    Button(action: {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            viewModel.geminiKey = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Paste API Key")
                }
                
                HStack {
                    Button("Save & Test") {
                        viewModel.saveGeminiKey()
                        viewModel.testGeminiConnection()
                    }
                    .disabled(viewModel.geminiKey.isEmpty)
                    
                    if viewModel.geminiTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if let status = viewModel.geminiStatus {
                        Text(status.message)
                            .font(.caption)
                            .foregroundColor(status.isSuccess ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Text("Usage: \(viewModel.geminiUsage) tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.geminiModels.isEmpty {
                    Text("Enter API Key to load models")
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("Model")
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                        Picker("", selection: $viewModel.selectedGeminiModel) {
                            ForEach(viewModel.geminiModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                Link("Get API Key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                    .font(.caption)
                
            }
            
            Section(header: Text("OpenAI GPT")) {
                HStack {
                    if showOpenAIKey {
                        TextField("API Key", text: $viewModel.openAIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $viewModel.openAIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showOpenAIKey.toggle() }) {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showOpenAIKey ? "Hide" : "Show")
                    
                    Button(action: {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            viewModel.openAIKey = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Paste API Key")
                }
                
                HStack {
                    Button("Save & Test") {
                        viewModel.saveOpenAIKey()
                        viewModel.testOpenAIConnection()
                    }
                    .disabled(viewModel.openAIKey.isEmpty)
                    
                    if viewModel.openAITesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if let status = viewModel.openAIStatus {
                        Text(status.message)
                            .font(.caption)
                            .foregroundColor(status.isSuccess ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Text("Usage: \(viewModel.openAIUsage) tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.openAIModels.isEmpty {
                    Text("Enter API Key to load models")
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("Model")
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                        Picker("", selection: $viewModel.selectedOpenAIModel) {
                            ForEach(viewModel.openAIModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                Link("Get API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }
            
            Section(header: Text("Mistral AI")) {
                HStack {
                    if showMistralKey {
                        TextField("API Key", text: $viewModel.mistralKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $viewModel.mistralKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showMistralKey.toggle() }) {
                        Image(systemName: showMistralKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showMistralKey ? "Hide" : "Show")
                    
                    Button(action: {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            viewModel.mistralKey = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Paste API Key")
                }
                
                HStack {
                    Button("Save & Test") {
                        viewModel.saveMistralKey()
                        viewModel.testMistralConnection()
                    }
                    .disabled(viewModel.mistralKey.isEmpty)
                    
                    if viewModel.mistralTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if let status = viewModel.mistralStatus {
                        Text(status.message)
                            .font(.caption)
                            .foregroundColor(status.isSuccess ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Text("Usage: \(viewModel.mistralUsage) tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.mistralModels.isEmpty {
                    Text("Enter API Key to load models")
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("Model")
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                        Picker("", selection: $viewModel.selectedMistralModel) {
                            ForEach(viewModel.mistralModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                Link("Get API Key", destination: URL(string: "https://console.mistral.ai/api-keys/")!)
                    .font(.caption)
            }
            
            Section(header: Text("Gemini CLI")) {
                VStack(alignment: .leading) {
                    Text("Executable Path")
                        .font(.body)
                        .foregroundColor(.primary)
                    HStack {
                        TextField("/path/to/gemini", text: $viewModel.geminiCLIPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse") {
                            // Try auto-detection first
                            if let detectedPath = GeminiIDEConnection.shared.findGeminiExecutable() {
                                autoDetectedPath = detectedPath
                                showAutoDetectAlert = true
                            } else {
                                // Fallback to manual browse if not found
                                openFilePanel()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Load API keys from keychain only when Engines tab is first accessed
            viewModel.loadKeysIfNeeded()
        }
        .alert("Gemini CLI Found", isPresented: $showAutoDetectAlert) {
            Button("Use Auto-Detected") {
                viewModel.geminiCLIPath = autoDetectedPath
                // Note: Auto-detected path usually doesn't need bookmark if sandbox is disabled
                // or if it's in a standard location.
            }
            Button("Browse Manually") {
                // Delay slightly to allow alert to dismiss before opening panel
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    openFilePanel()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("We found the Gemini CLI at:\n\(autoDetectedPath)\n\nDo you want to use this executable?")
        }
    }
    
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select Gemini CLI executable"
        panel.prompt = "Select"
        
        // Ensure panel runs on main thread
        DispatchQueue.main.async {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try viewModel.saveGeminiCLIBookmark(for: url)
                    } catch {
                        print("[SettingsView] Failed to save bookmark: \(error.localizedDescription)")
                        // Fallback: just save the path
                        viewModel.geminiCLIPath = url.path
                    }
                }
            }
        }
    }
}
