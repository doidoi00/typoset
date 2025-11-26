import SwiftUI
import AppKit

enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case pdf = "PDF"
    case image = "Image"
    case capture = "Capture"
}

enum HistorySortOrder: String, CaseIterable {
    case newest = "Latest First"
    case oldest = "Oldest First"
}

struct HistoryView: View {
    @State private var fileGroups: [FileGroup] = []
    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedSort: HistorySortOrder = .newest
    @EnvironmentObject var mainViewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter and Sort Controls
            VStack(alignment: .leading, spacing: 8) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(HistoryFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                
                Picker("Sort", selection: $selectedSort) {
                    ForEach(HistorySortOrder.allCases, id: \.self) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // File Groups List
            List(filteredAndSorted) { group in
                HStack(spacing: 12) {
                    // Thumbnail
                    if let image = group.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(Image(systemName: sourceIcon(for: group.source)))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.combinedText.prefix(60) + "...")
                            .font(.body)
                            .lineLimit(2)
                        
                        HStack {
                            Text(group.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(sourceLabel(for: group.source))
                                .font(.caption)
                                .padding(2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.vertical, 4)
                .onTapGesture {
                    mainViewModel.loadFileGroup(group)
                }
                .contextMenu {
                    Button("Copy Text") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(group.combinedText, forType: .string)
                    }
                }
            }
        }
        .onAppear(perform: loadHistory)
        .refreshable {
            loadHistory()
        }
    }
    
    private var filteredAndSorted: [FileGroup] {
        var filtered = fileGroups
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .pdf, .image, .capture:
            filtered = filtered.filter { $0.source == selectedFilter.rawValue.lowercased() }
        }
        
        // Apply sort
        switch selectedSort {
        case .newest:
            filtered.sort { $0.date > $1.date }
        case .oldest:
            filtered.sort { $0.date < $1.date }
        }
        
        return filtered
    }
    
    private func sourceIcon(for source: String) -> String {
        switch source {
        case "pdf", "file": return "doc"
        case "capture": return "camera.viewfinder"
        default: return "photo"
        }
    }
    
    private func sourceLabel(for source: String) -> String {
        switch source {
        case "pdf", "file": return "PDF"
        case "capture": return "Capture"
        case "image": return "Image"
        default: return source.capitalized
        }
    }
    
    private func loadHistory() {
        fileGroups = DatabaseService.shared.fetchGroupedHistory()
    }
}
