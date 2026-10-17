import Foundation

enum MusicImporter {
    @MainActor
    static func importFile(_ fileURL: URL) async -> Bool {
        let path = escapePath(fileURL.path)
        let source = """
        tell application "Music"
            set addedTrack to (add POSIX file "\(path)" to library playlist 1)
            try
                set loved of addedTrack to true
            end try
        end tell
        """
        return runScript(source)
    }

    @MainActor
    static func importToPlaylist(_ fileURL: URL, playlistName: String) async -> Bool {
        let path = escapePath(fileURL.path)
        let name = playlistName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source = """
        tell application "Music"
            set addedTrack to (add POSIX file "\(path)" to library playlist 1)
            try
                set loved of addedTrack to true
            end try

            set targetPlaylist to missing value
            try
                set targetPlaylist to user playlist "\(name)"
            end try
            if targetPlaylist is missing value then
                set targetPlaylist to make new user playlist with properties {name:"\(name)"}
            end if
            duplicate addedTrack to targetPlaylist
        end tell
        """
        return runScript(source)
    }

    @MainActor
    private static func runScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private static func escapePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
