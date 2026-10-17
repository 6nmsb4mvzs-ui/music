import Foundation

@Observable
final class UpdateChecker {
    var latestVersion: String?
    var releaseNotes: String?
    var downloadURL: URL?
    var isChecking = false
    var isUpdating = false
    var updateProgress = ""
    var updateError: String?
    var lastChecked: Date?

    private let currentVersion = "2.0.0"
    private let repoAPI = "https://api.github.com/repos/6nmsb4mvzs-ui/music/releases/latest"
    private let sourceArchive = "https://github.com/6nmsb4mvzs-ui/music/archive/refs/heads/main.zip"

    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return latest.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    func check() async {
        guard !isChecking else { return }
        await MainActor.run { isChecking = true }

        defer { Task { @MainActor in isChecking = false; lastChecked = Date() } }

        guard let url = URL(string: repoAPI) else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let tag = (json["tag_name"] as? String)?.replacingOccurrences(of: "v", with: "") ?? ""
            let notes = json["body"] as? String ?? ""
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            let dlURL = (zip?["browser_download_url"] as? String).flatMap(URL.init)

            await MainActor.run {
                latestVersion = tag
                releaseNotes = notes
                downloadURL = dlURL
            }
        } catch {}
    }

    func performUpdate() async {
        await MainActor.run {
            isUpdating = true
            updateError = nil
            updateProgress = "Downloading latest source..."
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("soundgrab_update_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            guard let archiveURL = URL(string: sourceArchive) else {
                throw UpdateError.failed("Invalid archive URL")
            }

            let (data, _) = try await URLSession.shared.data(from: archiveURL)
            let zipPath = tempDir.appendingPathComponent("source.zip")
            try data.write(to: zipPath)

            await MainActor.run { updateProgress = "Extracting..." }

            try await run("/usr/bin/unzip", args: ["-o", zipPath.path, "-d", tempDir.path])

            let extractedDir = tempDir.appendingPathComponent("music-main/SoundGrab")
            guard FileManager.default.fileExists(atPath: extractedDir.path) else {
                throw UpdateError.failed("Source not found in archive")
            }

            await MainActor.run { updateProgress = "Building (this may take a minute)..." }

            try await run("/usr/bin/swift", args: ["build", "-c", "release", "--package-path", extractedDir.path, "--quiet"])

            let newBinary = extractedDir.appendingPathComponent(".build/release/SoundGrab")
            guard FileManager.default.fileExists(atPath: newBinary.path) else {
                throw UpdateError.failed("Build produced no binary")
            }

            let currentBinary = ProcessInfo.processInfo.arguments[0]
            let currentURL = URL(fileURLWithPath: currentBinary)
                .resolvingSymlinksInPath()

            await MainActor.run { updateProgress = "Installing..." }

            let backupPath = currentURL.path + ".backup"
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.moveItem(atPath: currentURL.path, toPath: backupPath)
            try FileManager.default.copyItem(at: newBinary, to: currentURL)

            let script = """
            #!/bin/bash
            sleep 1
            "\(currentURL.path)" &
            rm -rf "\(tempDir.path)"
            rm -f "\(backupPath)"
            """
            let scriptPath = tempDir.appendingPathComponent("relaunch.sh")
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
            try await run("/bin/chmod", args: ["+x", scriptPath.path])

            await MainActor.run { updateProgress = "Relaunching..." }

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptPath.path]
            try launcher.run()

            exit(0)

        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            await MainActor.run {
                isUpdating = false
                updateError = error.localizedDescription
                updateProgress = ""
            }
        }
    }

    private func run(_ path: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = args
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()

            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let errPipe = p.standardError as? Pipe
                    let errData = errPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    let msg = String(data: errData, encoding: .utf8) ?? "exit \(p.terminationStatus)"
                    cont.resume(throwing: UpdateError.failed(msg))
                }
            }

            do { try proc.run() }
            catch { cont.resume(throwing: error) }
        }
    }
}

enum UpdateError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let msg): msg }
    }
}
