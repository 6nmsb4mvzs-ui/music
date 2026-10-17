import Foundation

@Observable
final class UpdateChecker {
    var latestVersion: String?
    var releaseNotes: String?
    var downloadURL: URL?
    var isChecking = false
    var lastChecked: Date?

    private let currentVersion = "2.0.0"
    private let repoAPI = "https://api.github.com/repos/6nmsb4mvzs-ui/music/releases/latest"

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
}
