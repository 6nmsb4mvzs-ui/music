import SwiftUI

enum Platform: String, CaseIterable, Identifiable, Codable {
    case soundcloud = "SoundCloud"
    case youtube = "YouTube"
    case instagram = "Instagram"
    case tiktok = "TikTok"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .soundcloud: "cloud.fill"
        case .youtube: "play.rectangle.fill"
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        }
    }

    var color: Color {
        switch self {
        case .soundcloud: .orange
        case .youtube: .red
        case .instagram: Color(red: 0.83, green: 0.18, blue: 0.55)
        case .tiktok: .cyan
        }
    }

    var hostPatterns: [String] {
        switch self {
        case .soundcloud: ["soundcloud.com"]
        case .youtube: ["youtube.com", "youtu.be", "music.youtube.com"]
        case .instagram: ["instagram.com"]
        case .tiktok: ["tiktok.com"]
        }
    }

    static func detect(from url: String) -> Platform? {
        let lower = url.lowercased()
        for platform in Platform.allCases {
            for pattern in platform.hostPatterns {
                if lower.contains(pattern) { return platform }
            }
        }
        return nil
    }
}

enum DownloadStatus: Equatable {
    case waiting
    case fetchingInfo
    case downloading
    case converting
    case ready
    case importing
    case done
    case failed(String)

    var label: String {
        switch self {
        case .waiting: "Queued"
        case .fetchingInfo: "Getting info..."
        case .downloading: "Downloading..."
        case .converting: "Converting to MP3..."
        case .ready: "Ready to import"
        case .importing: "Adding to Music..."
        case .done: "Done"
        case .failed(let msg): msg
        }
    }

    static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.waiting, .waiting), (.fetchingInfo, .fetchingInfo),
             (.downloading, .downloading), (.converting, .converting),
             (.ready, .ready), (.importing, .importing), (.done, .done):
            true
        case (.failed(let a), .failed(let b)):
            a == b
        default:
            false
        }
    }
}

@Observable
final class DownloadItem: Identifiable {
    let id = UUID()
    let url: String
    let platform: Platform
    var title: String
    var artist: String
    var status: DownloadStatus = .waiting
    var progress: Double = 0
    var filePath: URL?
    var coverData: Data?
    var importToMusic: Bool
    var editedTitle: String?
    var editedArtist: String?
    var editedCover: Data?
    var duration: Double?

    init(url: String, platform: Platform, title: String = "Loading...", artist: String = "", importToMusic: Bool = true) {
        self.url = url
        self.platform = platform
        self.title = title
        self.artist = artist
        self.importToMusic = importToMusic
    }

    var displayTitle: String { editedTitle ?? title }
    var displayArtist: String { editedArtist ?? artist }
}

@Observable
final class TrackPreview: Identifiable {
    let id = UUID()
    let url: String
    let platform: Platform
    var title: String = ""
    var artist: String = ""
    var duration: Double?
    var thumbnailData: Data?
    var isPlaylist: Bool = false
    var trackCount: Int = 0

    init(url: String, platform: Platform) {
        self.url = url
        self.platform = platform
    }

    var durationText: String? {
        guard let d = duration, d > 0 else { return nil }
        let m = Int(d) / 60
        let s = Int(d) % 60
        return String(format: "%d:%02d", m, s)
    }
}

enum DownloadError: Error, LocalizedError {
    case notFound
    case downloadFailed(String)
    case conversionFailed
    case durationMismatch

    var errorDescription: String? {
        switch self {
        case .notFound: "Track not found"
        case .downloadFailed(let msg): msg
        case .conversionFailed: "Audio conversion failed"
        case .durationMismatch: "Duration verification failed — possible wrong track"
        }
    }
}
