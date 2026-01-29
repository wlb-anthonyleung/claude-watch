import Foundation

enum CCUsageError: Error, LocalizedError {
    case processFailure(String)
    case decodingFailure(Error)
    case npxNotFound

    var errorDescription: String? {
        switch self {
        case .processFailure(let msg): return "ccusage failed: \(msg)"
        case .decodingFailure(let err): return "JSON decode error: \(err.localizedDescription)"
        case .npxNotFound: return "npx not found. Ensure Node.js is installed."
        }
    }
}

actor CCUsageService {
    var npxPath: String

    init(npxPath: String = AppConstants.defaultNpxPath) {
        self.npxPath = npxPath
    }

    func updateNpxPath(_ path: String) {
        self.npxPath = path
    }

    func fetchUsage(since date: Date) async throws -> CCUsageResponse {
        let dateString = Self.formatDate(date)
        let arguments = ["ccusage", "--json", "--since", dateString, "--offline"]

        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: npxPath,
            arguments: arguments
        )

        guard exitCode == 0 else {
            throw CCUsageError.processFailure(stderr)
        }

        guard let data = stdout.data(using: .utf8) else {
            throw CCUsageError.processFailure("Empty output")
        }

        do {
            return try JSONDecoder().decode(CCUsageResponse.self, from: data)
        } catch {
            throw CCUsageError.decodingFailure(error)
        }
    }

    /// Fetches session data for a specific date.
    func fetchSessions(for date: Date) async throws -> CCSessionResponse {
        let dateString = Self.formatDate(date)
        let arguments = ["ccusage", "session", "--json", "--since", dateString, "--until", dateString, "--offline"]

        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: npxPath,
            arguments: arguments
        )

        guard exitCode == 0 else {
            throw CCUsageError.processFailure(stderr)
        }

        guard let data = stdout.data(using: .utf8) else {
            throw CCUsageError.processFailure("Empty output")
        }

        do {
            return try JSONDecoder().decode(CCSessionResponse.self, from: data)
        } catch {
            throw CCUsageError.decodingFailure(error)
        }
    }

    private func runProcess(executablePath: String, arguments: [String]) async throws -> (String, String, Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // GUI apps don't inherit the user's shell PATH
            var env = ProcessInfo.processInfo.environment
            let additionalPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = (additionalPaths + [currentPath]).joined(separator: ":")
            process.environment = env

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: (stdout, stderr, process.terminationStatus))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
