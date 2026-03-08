import Foundation
import Darwin

enum RuntimePaths {
    static func realUserHomePath() -> String {
        if let pw = getpwuid(getuid()) {
            let value = String(cString: pw.pointee.pw_dir)
            if !value.isEmpty {
                return value
            }
        }

        let fmHome = FileManager.default.homeDirectoryForCurrentUser.path
        if !fmHome.isEmpty {
            return fmHome
        }

        return NSHomeDirectory()
    }

    static func processEnvironmentForUserHome() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = realUserHomePath()
        env["HOME"] = home

        let requiredPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(home)/.local/bin",
            "\(home)/go/bin"
        ]
        let existingPath = env["PATH"] ?? ""
        let existingParts = existingPath.split(separator: ":").map(String.init)
        var merged: [String] = []
        var seen = Set<String>()
        for path in requiredPaths + existingParts {
            guard !path.isEmpty else { continue }
            if seen.insert(path).inserted {
                merged.append(path)
            }
        }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    static func resolveBinaryPath(_ name: String) -> String? {
        let home = realUserHomePath()
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "\(home)/go/bin/\(name)"
        ]

        for path in candidates where isExecutableFile(path) {
            return path
        }

        if let shellLocated = try? runShellCommand("command -v \(name)") {
            let trimmed = shellLocated.trimmingCharacters(in: .whitespacesAndNewlines)
            if isExecutableFile(trimmed) {
                return trimmed
            }
        }

        return nil
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private static func runShellCommand(_ command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = processEnvironmentForUserHome()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
