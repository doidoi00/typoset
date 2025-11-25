import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @EnvironmentObject var viewModel: MainViewModel
    
    var body: some View {
        Group {
            if viewModel.currentImage == nil && viewModel.recognizedText.isEmpty {
                // Welcome Screen
                WelcomeView()
            } else {
                // Full Interface
                FullInterfaceView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var viewModel: MainViewModel
    
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Text("Drop some images or PDF files here")
                        .font(.title3)
                    Text("...or use the screenshot, photo or scan functions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("to get started.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { viewModel.importFile(allowedTypes: [.image]) }) {
                        VStack {
                            Image(systemName: "photo")
                                .font(.title)
                            Text("Import Image")
                                .font(.caption)
                        }
                        .frame(width: 100, height: 80)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { viewModel.importFile(allowedTypes: [.pdf]) }) {
                        VStack {
                            Image(systemName: "doc")
                                .font(.title)
                            Text("Import PDF")
                                .font(.caption)
                        }
                        .frame(width: 100, height: 80)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { viewModel.captureScreen() }) {
                        VStack {
                            Image(systemName: "camera.viewfinder")
                                .font(.title)
                            Text("Capture Screen")
                                .font(.caption)
                        }
                        .frame(width: 100, height: 80)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 40)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
                provider.loadObject(ofClass: NSImage.self) { image, error in
                    if let image = image as? NSImage {
                        Task {
                            await viewModel.processImage(image, source: "file")
                            DispatchQueue.main.async {
                                viewModel.currentImage = image
                                viewModel.pdfDocument = nil
                            }
                        }
                    }
                }
                return true
            }
            return false
        }
    }
}

struct FullInterfaceView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var showSidebar = true
    @State private var selectedSidebarTab: SidebarTab = .history
    
    enum SidebarTab: String, CaseIterable {
        case history = "History"
        case favorites = "Favorites"
        
        var icon: String {
            switch self {
            case .history: return "clock"
            case .favorites: return "star"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Icon Bar - Always visible
            VStack(spacing: 8) {
                // Sidebar Toggle at top
                Button(action: { showSidebar.toggle() }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
                
                Divider()
                    .padding(.horizontal, 8)
                
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedSidebarTab = tab
                        if !showSidebar {
                            showSidebar = true
                        }
                    }) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .background(selectedSidebarTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help(tab.rawValue)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(width: 50)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Sidebar Content - Conditional
            if showSidebar {
                VStack(spacing: 0) {
                    // Tab Content
                    switch selectedSidebarTab {
                    case .history:
                        HistoryView()
                    case .favorites:
                        FavoritesView()
                    }
                }
                .frame(minWidth: 200, maxWidth: 300)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            
            // Main Content
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Picker("Engine", selection: $viewModel.selectedEngine) {
                        Text("Apple Vision").tag("Apple Vision")
                        Text("Gemini").tag("Gemini")
                        Text("GPT").tag("GPT")
                        Text("Mistral").tag("Mistral")
                        Text("Gemini CLI").tag("Gemini CLI")
                    }
                    .frame(width: 150)
                    
                    Spacer()
                    
                    Button(action: { viewModel.importFile() }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(action: viewModel.captureScreen) {
                        Label("Capture", systemImage: "camera.viewfinder")
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                
                // Split View: Image & Text
                HSplitView {
                    // Image Preview
                    ZStack(alignment: .bottom) {
                        ZStack {
                            Color(nsColor: .windowBackgroundColor)
                            if let image = viewModel.currentImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                    Text("Drag & Drop Image Here")
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                        .frame(minWidth: 300, maxHeight: .infinity)
                        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                            if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
                                provider.loadObject(ofClass: NSImage.self) { image, error in
                                    if let image = image as? NSImage {
                                        Task {
                                            await viewModel.processImage(image, source: "file")
                                            DispatchQueue.main.async {
                                                viewModel.currentImage = image
                                                viewModel.pdfDocument = nil
                                            }
                                        }
                                    }
                                }
                                return true
                            }
                            return false
                        }
                        
                        // PDF Navigation Bar & Re-OCR Button
                        HStack(spacing: 16) {
                            if viewModel.pdfDocument != nil {
                                Button(action: viewModel.previousPage) {
                                    Image(systemName: "chevron.left")
                                }
                                .disabled(viewModel.currentPageIndex <= 0)
                                
                                Text("\(viewModel.currentPageIndex + 1) / \(viewModel.totalPages)")
                                    .font(.system(.body, design: .monospaced))
                                
                                Button(action: viewModel.nextPage) {
                                    Image(systemName: "chevron.right")
                                }
                                .disabled(viewModel.currentPageIndex >= viewModel.totalPages - 1)
                                
                                Divider()
                                    .frame(height: 20)
                            }
                            
                            // Re-OCR button (always visible when image is present)
                            Button(action: viewModel.reprocessCurrentPage) {
                                Label("Re-OCR", systemImage: "arrow.clockwise")
                            }
                            .disabled(viewModel.isProcessing || viewModel.currentImage == nil)
                            .help("Reprocess with current engine")
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 16)

                    }
                    
                    // Text Result
                    TextEditor(text: $viewModel.recognizedText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 300)
                }
                
                // Action Bar
                HStack {
                    Button("Copy Text") {
                        viewModel.copyToClipboard()
                    }
                    
                    Menu("Export") {
                        Button("Export as TXT") {
                            viewModel.exportAsText()
                        }
                        Button("Export as Markdown") {
                            viewModel.exportAsMarkdown()
                        }
                        Button("Export as JSON") {
                            viewModel.exportAsJSON()
                        }
                        Button("Export as PDF") {
                            viewModel.exportAsPDF()
                        }
                    }
                    .disabled(viewModel.recognizedText.isEmpty)
                    
                    Button(action: { viewModel.toggleFavorite() }) {
                        Image(systemName: viewModel.isCurrentItemFavorited ? "star.fill" : "star")
                    }
                    .help(viewModel.isCurrentItemFavorited ? "Remove from Favorites" : "Add to Favorites")
                    
                    Spacer()
                    Toggle("Auto-detect Language", isOn: .constant(true))
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }
    
    private func addToFavorites() {
        guard !viewModel.recognizedText.isEmpty else { return }
        FavoritesManager.shared.add(
            text: viewModel.recognizedText,
            image: viewModel.currentImage
        )
    }
}

// Favorites View
struct FavoritesView: View {
    @State private var favorites: [FavoriteItem] = []
    @EnvironmentObject var mainViewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if favorites.isEmpty {
                // Empty State - Centered
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Favorites Yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap the star button to save OCR results")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            } else {
                // List fills entire space
                List {
                    ForEach(favorites) { item in
                        HStack(spacing: 12) {
                            if let image = item.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text.prefix(50) + "...")
                                    .font(.body)
                                    .lineLimit(2)
                                Text(item.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .onTapGesture {
                            loadFavorite(item)
                        }
                        .contextMenu {
                            Button("Remove from Favorites") {
                                removeFavorite(item)
                            }
                            Button("Copy Text") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(item.text, forType: .string)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: loadFavorites)
    }
    
    private func loadFavorites() {
        favorites = FavoritesManager.shared.fetchAll()
    }
    
    private func loadFavorite(_ item: FavoriteItem) {
        mainViewModel.recognizedText = item.text
        if let image = item.image {
            mainViewModel.currentImage = image
        }
    }
    
    private func removeFavorite(_ item: FavoriteItem) {
        FavoritesManager.shared.remove(id: item.id)
        loadFavorites()
    }
}
