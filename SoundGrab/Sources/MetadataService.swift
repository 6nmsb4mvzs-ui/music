import Foundation
import AppKit

enum MetadataService {
    static func extractCoverArt(from file: URL, ffmpegPath: String) async -> Data? {
        let coverPath = file.deletingLastPathComponent().appendingPathComponent("cover_extract.jpg").path
        let args = ["-i", file.path, "-an", "-vcodec", "mjpeg", "-frames:v", "1", "-y", coverPath]

        do {
            let (_, _) = try await exec(ffmpegPath, arguments: args)
            let data = try Data(contentsOf: URL(fileURLWithPath: coverPath))
            try? FileManager.default.removeItem(atPath: coverPath)
            return data
        } catch {
            return nil
        }
    }

    static func applyCoverArt(_ coverData: Data, to file: URL, ffmpegPath: String) async -> Bool {
        let dir = file.deletingLastPathComponent()
        let coverPath = dir.appendingPathComponent("cover_apply.jpg").path
        let outPath = dir.appendingPathComponent("tagged_\(file.lastPathComponent)").path

        do {
            try coverData.write(to: URL(fileURLWithPath: coverPath))

            let args = [
                "-i", file.path, "-i", coverPath,
                "-map", "0:a", "-map", "1:0",
                "-c:a", "copy", "-id3v2_version", "3",
                "-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)",
                "-disposition:v:0", "attached_pic",
                "-y", outPath
            ]

            let (_, _) = try await exec(ffmpegPath, arguments: args)

            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(atPath: outPath, toPath: file.path)
            try? FileManager.default.removeItem(atPath: coverPath)
            return true
        } catch {
            try? FileManager.default.removeItem(atPath: outPath)
            try? FileManager.default.removeItem(atPath: coverPath)
            return false
        }
    }

    static func applyMetadata(title: String?, artist: String?, to file: URL, ffmpegPath: String) async -> Bool {
        let dir = file.deletingLastPathComponent()
        let outPath = dir.appendingPathComponent("meta_\(file.lastPathComponent)").path

        var args = ["-i", file.path]
        if let t = title { args += ["-metadata", "title=\(t)"] }
        if let a = artist { args += ["-metadata", "artist=\(a)"] }
        args += ["-c", "copy", "-y", outPath]

        do {
            let (_, _) = try await exec(ffmpegPath, arguments: args)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(atPath: outPath, toPath: file.path)
            return true
        } catch {
            try? FileManager.default.removeItem(atPath: outPath)
            return false
        }
    }

    private static func exec(_ path: String, arguments: [String]) async throws -> (String, String) {
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
                    cont.resume(throwing: DownloadError.downloadFailed(err.isEmpty ? out : err))
                }
            }

            do { try proc.run() }
            catch { cont.resume(throwing: error) }
        }
    }
}
