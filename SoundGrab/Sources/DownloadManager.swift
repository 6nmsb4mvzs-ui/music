import Foundation

final class LockedBuffer: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()
    func append(_ s: String) { lock.lock(); buffer += s; lock.unlock() }
    func read() -> String { lock.lock(); defer { lock.unlock() }; return buffer }
}

@Observable @MainActor
final class DownloadManager {
    var items: [DownloadItem] = []
    var isCheckingDeps = true
    var dependenciesReady = false
    var isInstalling = false
    var installOutput = ""

    var ytdlpPath: String?
    var ffmpegPath: String?
    var ffprobePath: String?

    let settings = AppSettings()
    let updateChecker = UpdateChecker()

    let downloadDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/SoundGrab")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let searchPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/local/bin",
        NSHomeDirectory() + "/.local/bin"
    ]

    private var activeTasks = 0
    private let maxConcurrent = 3

    init() {
        Task { await checkDependencies() }
    }

    func checkDependencies() async {
        isCheckingDeps = true
        ytdlpPath = findBinary("yt-dlp")
        ffmpegPath = findBinary("ffmpeg")
        ffprobePath = findBinary("ffprobe")
        dependenciesReady = ytdlpPath != nil && ffmpegPath != nil
        isCheckingDeps = false
    }

    func installDependencies() async {
        isInstalling = true
        installOutput = "Installing via Homebrew..."

        let brewPath = findBinary("brew") ?? "/opt/homebrew/bin/brew"
        do {
            let (out, _) = try await Self.exec(brewPath, arguments: ["install", "yt-dlp", "ffmpeg"])
            installOutput = out.contains("already installed") ? "Already installed" : "Installed"
        } catch {
            installOutput = "Install failed: \(error.localizedDescription)"
        }

        await checkDependencies()
        isInstalling = false
    }

    func updateYTDLP() async {
        isInstalling = true
        installOutput = "Updating yt-dlp..."

        if let path = ytdlpPath {
            do {
                let (_, _) = try await Self.exec(path, arguments: ["--update"])
                installOutput = "Updated"
            } catch {
                installOutput = "Update failed"
            }
        }

        isInstalling = false
        try? await Task.sleep(for: .seconds(2))
        installOutput = ""
    }

    // MARK: - Preview

    func fetchPreview(_ urlString: String) async -> TrackPreview? {
        guard let platform = Platform.detect(from: urlString),
              let ytdlp = ytdlpPath else { return nil }

        let preview = TrackPreview(url: urlString, platform: platform)

        let isPlaylist = await checkIfPlaylist(urlString, ytdlp: ytdlp)
        preview.isPlaylist = isPlaylist

        if isPlaylist {
            do {
                let (output, _) = try await Self.exec(ytdlp, arguments: [
                    "--flat-playlist", "--print", "id", urlString
                ])
                let count = output.components(separatedBy: "\n").filter { !$0.isEmpty }.count
                preview.trackCount = count
                preview.title = "Playlist"
            } catch {}
        } else {
            do {
                let (info, _) = try await Self.exec(ytdlp, arguments: [
                    "--no-playlist", "--print",
                    "%(title)s\n%(uploader)s\n%(duration)s\n%(thumbnail)s",
                    urlString
                ])
                let parts = info.components(separatedBy: "\n").filter { !$0.isEmpty }
                if parts.count >= 1 { preview.title = parts[0] }
                if parts.count >= 2 { preview.artist = parts[1] }
                if parts.count >= 3 { preview.duration = Double(parts[2]) }
                if parts.count >= 4, let thumbURL = URL(string: parts[3]) {
                    if let (data, _) = try? await URLSession.shared.data(from: thumbURL) {
                        preview.thumbnailData = data
                    }
                }
            } catch {}
        }

        return preview
    }

    // MARK: - Submit

    func submitURL(_ urlString: String, importToMusic: Bool, editedTitle: String? = nil, editedArtist: String? = nil) async {
        guard let platform = Platform.detect(from: urlString) else { return }

        guard let ytdlp = ytdlpPath, let ffmpeg = ffmpegPath else { return }

        let isPlaylist = await checkIfPlaylist(urlString, ytdlp: ytdlp)

        if isPlaylist {
            await downloadPlaylist(urlString, platform: platform, importToMusic: importToMusic, ytdlp: ytdlp, ffmpeg: ffmpeg)
        } else {
            let item = DownloadItem(url: urlString, platform: platform, importToMusic: importToMusic)
            if let t = editedTitle { item.editedTitle = t }
            if let a = editedArtist { item.editedArtist = a }
            items.insert(item, at: 0)
            await processItem(item, ytdlp: ytdlp, ffmpeg: ffmpeg)
        }
    }

    // MARK: - Playlist

    private func downloadPlaylist(_ url: String, platform: Platform, importToMusic: Bool, ytdlp: String, ffmpeg: String) async {
        do {
            let (output, _) = try await Self.exec(ytdlp, arguments: [
                "--flat-playlist", "--print", "url", "--print", "title", url
            ])

            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 2 else {
                let item = DownloadItem(url: url, platform: platform, importToMusic: importToMusic)
                items.insert(item, at: 0)
                await processItem(item, ytdlp: ytdlp, ffmpeg: ffmpeg)
                return
            }

            var trackURLs: [(String, String)] = []
            var i = 0
            while i + 1 < lines.count {
                trackURLs.append((lines[i], lines[i + 1]))
                i += 2
            }

            let insertBase = 0
            var newItems: [DownloadItem] = []
            for (trackURL, title) in trackURLs {
                let item = DownloadItem(url: trackURL, platform: platform, title: title, importToMusic: importToMusic)
                newItems.append(item)
            }

            items.insert(contentsOf: newItems, at: insertBase)

            await withTaskGroup(of: Void.self) { group in
                for item in newItems {
                    group.addTask { [self] in
                        await self.processItem(item, ytdlp: ytdlp, ffmpeg: ffmpeg)
                    }
                }
            }
        } catch {
            let item = DownloadItem(url: url, platform: platform, importToMusic: importToMusic)
            item.status = .failed("Playlist fetch failed: \(error.localizedDescription)")
            items.insert(item, at: 0)
        }
    }

    // MARK: - Process single item

    private func processItem(_ item: DownloadItem, ytdlp: String, ffmpeg: String) async {
        item.status = .fetchingInfo

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("soundgrab_\(item.id.uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let (info, _) = try await Self.exec(ytdlp, arguments: [
                "--no-playlist", "--print", "%(title)s\n%(uploader)s\n%(duration)s", item.url
            ])

            let infoParts = info.components(separatedBy: "\n").filter { !$0.isEmpty }
            if infoParts.count >= 1 { item.title = infoParts[0] }
            if infoParts.count >= 2 { item.artist = infoParts[1] }
            if infoParts.count >= 3 { item.duration = Double(infoParts[2]) }

            item.status = .downloading

            let outTemplate = tempDir.appendingPathComponent("%(title)s.%(ext)s").path
            try await runDownload(item: item, ytdlp: ytdlp, ffmpeg: ffmpeg, outTemplate: outTemplate)

            item.status = .converting

            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let downloaded = files.first(where: { $0.pathExtension == "mp3" }) ?? files.first else {
                throw DownloadError.downloadFailed("No output file found")
            }

            if downloaded.pathExtension != "mp3" {
                let mp3Path = downloaded.deletingPathExtension().appendingPathExtension("mp3")
                let (_, _) = try await Self.exec(ffmpeg, arguments: [
                    "-i", downloaded.path, "-ab", "320k", "-y", mp3Path.path
                ])
                try? FileManager.default.removeItem(at: downloaded)
            }

            let mp3Files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "mp3" }
            guard let mp3 = mp3Files.first else { throw DownloadError.conversionFailed }

            if let expected = item.duration, let probe = ffprobePath {
                let actual = await probeAudioDuration(probe: probe, file: mp3)
                if let actual, abs(actual - expected) > max(expected * 0.2, 5) {
                    throw DownloadError.durationMismatch
                }
            }

            if let coverData = await MetadataService.extractCoverArt(from: mp3, ffmpegPath: ffmpeg) {
                item.coverData = coverData
            }

            let safeName = sanitizeFilename(item.displayTitle) + ".mp3"
            let dest = downloadDir.appendingPathComponent(safeName)
            let finalDest = uniquePath(for: dest)

            try FileManager.default.moveItem(at: mp3, to: finalDest)
            item.filePath = finalDest

            if item.editedTitle != nil || item.editedArtist != nil {
                let _ = await MetadataService.applyMetadata(
                    title: item.editedTitle, artist: item.editedArtist,
                    to: finalDest, ffmpegPath: ffmpeg
                )
            }

            if let coverData = item.editedCover {
                let _ = await MetadataService.applyCoverArt(coverData, to: finalDest, ffmpegPath: ffmpeg)
            }

            if item.importToMusic && settings.autoImport {
                item.status = .importing

                if settings.playlistEnabled {
                    let plName: String
                    if settings.separatePlaylists {
                        plName = "\(settings.playlistName) - \(item.platform.rawValue)"
                    } else {
                        plName = settings.playlistName
                    }
                    let _ = await MusicImporter.importToPlaylist(finalDest, playlistName: plName)
                } else {
                    let _ = await MusicImporter.importFile(finalDest)
                }
            }

            item.status = .done

        } catch {
            item.status = .failed(error.localizedDescription)
        }
    }

    // MARK: - yt-dlp download with progress

    private func runDownload(item: DownloadItem, ytdlp: String, ffmpeg: String, outTemplate: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ytdlp)
            proc.arguments = [
                "--no-playlist",
                "-x", "--audio-format", "mp3", "--audio-quality", "0",
                "--ffmpeg-location", (ffmpeg as NSString).deletingLastPathComponent,
                "--newline",
                "-o", outTemplate,
                item.url
            ]

            let outPipe = Pipe()
            let errBuf = LockedBuffer()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                errBuf.append(str)
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                for line in str.components(separatedBy: "\n") {
                    if let pct = self.parseProgress(line) {
                        Task { @MainActor in item.progress = pct }
                    }
                }
            }

            proc.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let errMsg = errBuf.read()
                    cont.resume(throwing: DownloadError.downloadFailed(
                        errMsg.isEmpty ? "Download failed (exit \(p.terminationStatus))" : errMsg
                    ))
                }
            }

            do { try proc.run() }
            catch { cont.resume(throwing: error) }
        }
    }

    private nonisolated func parseProgress(_ line: String) -> Double? {
        guard line.contains("[download]") && line.contains("%") else { return nil }
        let parts = line.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
        for part in parts {
            if part.hasSuffix("%"), let val = Double(part.dropLast()) {
                return min(val / 100.0, 1.0)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func checkIfPlaylist(_ url: String, ytdlp: String) async -> Bool {
        do {
            let (output, _) = try await Self.exec(ytdlp, arguments: [
                "--flat-playlist", "--print", "id", url
            ])
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            return lines.count > 1
        } catch {
            return false
        }
    }

    private func probeAudioDuration(probe: String, file: URL) async -> Double? {
        do {
            let (out, _) = try await Self.exec(probe, arguments: [
                "-v", "quiet", "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1", file.path
            ])
            return Double(out.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return nil
        }
    }

    func clearCompleted() {
        items.removeAll { $0.status == .done }
    }

    private func findBinary(_ name: String) -> String? {
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }

    private func uniquePath(for url: URL) -> URL {
        var dest = url
        var counter = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = url.deletingPathExtension().lastPathComponent + " (\(counter))"
            dest = url.deletingLastPathComponent()
                .appendingPathComponent(name)
                .appendingPathExtension(url.pathExtension)
            counter += 1
        }
        return dest
    }

    nonisolated static func exec(_ path: String, arguments: [String]) async throws -> (String, String) {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            proc.terminationHandler = { p in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""

                if p.terminationStatus == 0 {
                    cont.resume(returning: (out, err))
                } else {
                    let msg = err.isEmpty ? out : err
                    cont.resume(throwing: DownloadError.downloadFailed(msg))
                }
            }

            do { try proc.run() }
            catch { cont.resume(throwing: error) }
        }
    }
}
