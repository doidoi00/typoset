import Foundation

class GeminiIDEConnection {
    static let shared = GeminiIDEConnection()
    
    private let fileManager = FileManager.default
    
    // Stable temporary directory for the "IDE" workspace
    private var workspaceURL: URL {
        let tempDir = fileManager.temporaryDirectory
        let workspaceDir = tempDir.appendingPathComponent("GeminiCLIWorkspace", isDirectory: true)
        
        if !fileManager.fileExists(atPath: workspaceDir.path) {
            try? fileManager.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        }
        
        return workspaceDir
    }
    
    // Generate environment variables for the CLI process
    func getEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        
        // Set the workspace path env var that Gemini CLI looks for
        environment["GEMINI_CLI_IDE_WORKSPACE_PATH"] = workspaceURL.path
        
        // Set a custom alias to identify as "Antigravity" (or Typoset)
        environment["ANTIGRAVITY_CLI_ALIAS"] = "true"
        
        // Enhance PATH to include common locations
        var additionalPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin"
        ]
        
        // Manually expand NVM paths since wildcards don't work in PATH
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        
        if let nodeVersions = try? fileManager.contentsOfDirectory(atPath: nvmVersionsDir) {
            // Add all node version bin directories
            for version in nodeVersions {
                let binPath = "\(nvmVersionsDir)/\(version)/bin"
                if fileManager.fileExists(atPath: binPath) {
                    additionalPaths.append(binPath)
                }
            }
        }
        
        let currentPath = environment["PATH"] ?? ""
        let newPath = (additionalPaths + currentPath.split(separator: ":").map(String.init)).joined(separator: ":")
        environment["PATH"] = newPath
        
        return environment
    }
    
    // Helper to save a file to the workspace
    func saveFileToWorkspace(data: Data, filename: String) throws -> String {
        let fileURL = workspaceURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL.path
    }
    
    // Helper to clean up a file from the workspace
    func removeFileFromWorkspace(filename: String) {
        let fileURL = workspaceURL.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }
    
    // Get the workspace directory path
    var workspacePath: String {
        return workspaceURL.path
    }
    
    // Attempt to find the gemini executable using 'which' and manual fallbacks
    func findGeminiExecutable() -> String? {
        // 1. Try using 'which' command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gemini"]
        process.environment = getEnvironment()
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    return path
                }
            }
        } catch {
            print("Failed to run 'which gemini': \(error)")
        }
        
        // 2. Manual fallback checks for common locations
        let commonPaths = [
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini",
            "/usr/bin/gemini"
        ]
        
        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        
        // 3. Check NVM paths (wildcard expansion)
        // Since we can't easily do wildcard expansion with FileManager, we can check the .nvm directory structure manually if needed.
        // For now, let's try to construct a path if NVM_DIR is present or check standard ~/.nvm location.
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        
        if let nodeVersions = try? fileManager.contentsOfDirectory(atPath: nvmVersionsDir) {
            // Sort versions to try newest first?
            for version in nodeVersions {
                let possiblePath = "\(nvmVersionsDir)/\(version)/bin/gemini"
                if fileManager.fileExists(atPath: possiblePath) {
                    return possiblePath
                }
            }
        }
        
        return nil
    }
}
