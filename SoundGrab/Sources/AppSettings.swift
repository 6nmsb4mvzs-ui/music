import Foundation

@Observable
final class AppSettings {
    private let defaults = UserDefaults(suiteName: "com.soundgrab.settings") ?? .standard

    var autoImport: Bool {
        didSet { defaults.set(autoImport, forKey: "autoImport") }
    }

    var playlistEnabled: Bool {
        didSet { defaults.set(playlistEnabled, forKey: "playlistEnabled") }
    }

    var separatePlaylists: Bool {
        didSet { defaults.set(separatePlaylists, forKey: "separatePlaylists") }
    }

    var playlistName: String {
        didSet { defaults.set(playlistName, forKey: "playlistName") }
    }

    init() {
        let d = UserDefaults(suiteName: "com.soundgrab.settings") ?? .standard
        self.autoImport = d.object(forKey: "autoImport") as? Bool ?? true
        self.playlistEnabled = d.object(forKey: "playlistEnabled") as? Bool ?? false
        self.separatePlaylists = d.object(forKey: "separatePlaylists") as? Bool ?? false
        self.playlistName = d.string(forKey: "playlistName") ?? "SoundGrab"
    }
}
