import SwiftUI

struct SettingsView: View {
    @Environment(DownloadManager.self) private var manager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                importSection
                playlistSection
                updateSection
                aboutSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await manager.updateChecker.check()
        }
    }

    // MARK: - Import

    @ViewBuilder
    private var importSection: some View {
        SettingsCard(title: "Import", icon: "music.note") {
            Toggle("Auto-import to Apple Music after download", isOn: Bindable(manager.settings).autoImport)
                .font(.body)

            Text("When enabled, tracks are added to your Music library automatically. They sync to your phone via iCloud Music Library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Playlists

    @ViewBuilder
    private var playlistSection: some View {
        SettingsCard(title: "Playlists", icon: "music.note.list") {
            Toggle("Add songs to playlist", isOn: Bindable(manager.settings).playlistEnabled)
                .font(.body)

            if manager.settings.playlistEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Playlist name:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Playlist name", text: Bindable(manager.settings).playlistName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                    }

                    Toggle("Separate playlists per source", isOn: Bindable(manager.settings).separatePlaylists)
                        .font(.body)

                    if manager.settings.separatePlaylists {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Platform.allCases) { p in
                                HStack(spacing: 6) {
                                    Image(systemName: p.icon)
                                        .font(.caption)
                                        .foregroundStyle(p.color)
                                        .frame(width: 16)
                                    Text("\(manager.settings.playlistName) - \(p.rawValue)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - Updates

    @ViewBuilder
    private var updateSection: some View {
        SettingsCard(title: "Updates", icon: "arrow.triangle.2.circlepath") {
            if manager.updateChecker.isUpdating {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(manager.updateChecker.updateProgress)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Text("Don't close the app during update")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if manager.updateChecker.isChecking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking for updates...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else if manager.updateChecker.updateAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(.blue)
                        Text("Version \(manager.updateChecker.latestVersion ?? "") available")
                            .font(.body.bold())
                    }

                    if let notes = manager.updateChecker.releaseNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }

                    Button("Update Now") {
                        Task { await manager.updateChecker.performUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("You're on the latest version (2.0.0)")
                        .font(.body)
                }

                Button("Check Again") {
                    Task { await manager.updateChecker.check() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let err = manager.updateChecker.updateError {
                Text("Update failed: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let last = manager.updateChecker.lastChecked {
                Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        SettingsCard(title: "About", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text("SoundGrab v2.0.0")
                    .font(.body.bold())
                Text("Download audio from SoundCloud, YouTube, Instagram, and TikTok as 320kbps MP3.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("yt-dlp")
                            .font(.caption.bold())
                        Text(manager.ytdlpPath ?? "Not found")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ffmpeg")
                            .font(.caption.bold())
                        Text(manager.ffmpegPath ?? "Not found")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Card

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
