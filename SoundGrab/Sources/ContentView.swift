import SwiftUI

// MARK: - Root

struct ContentView: View {
    @Environment(DownloadManager.self) private var manager

    var body: some View {
        Group {
            if manager.isCheckingDeps {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Checking for yt-dlp and ffmpeg...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !manager.dependenciesReady {
                SetupView()
            } else {
                MainView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Setup

struct SetupView: View {
    @Environment(DownloadManager.self) private var manager

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Install Dependencies")
                .font(.title2.bold())

            Text("SoundGrab uses yt-dlp and ffmpeg to download\nand convert audio at 320kbps MP3.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                DepRow(name: "yt-dlp", installed: manager.ytdlpPath != nil)
                DepRow(name: "ffmpeg", installed: manager.ffmpegPath != nil)
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if manager.isInstalling {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(manager.installOutput)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                if !manager.installOutput.isEmpty {
                    Text(manager.installOutput)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Install via Homebrew") {
                    Task { await manager.installDependencies() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DepRow: View {
    let name: String
    let installed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(installed ? .green : .red)
            Text(name)
                .font(.body.monospaced())
            Spacer()
            Text(installed ? "Found" : "Missing")
                .font(.caption)
                .foregroundStyle(installed ? .green : .secondary)
        }
    }
}

// MARK: - Main

struct MainView: View {
    @Environment(DownloadManager.self) private var manager
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SoundGrab")
                    .font(.title3.bold())
                Spacer()

                Picker("", selection: $selectedTab) {
                    Text("Downloads").tag(0)
                    Text("Settings").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if selectedTab == 0 {
                DownloadsView()
            } else {
                SettingsView()
            }
        }
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @Environment(DownloadManager.self) private var manager
    @State private var urlText = ""
    @State private var importToMusic = true
    @State private var errorMessage: String?
    @State private var detectedPlatform: Platform?
    @State private var editingItem: DownloadItem?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        if urlText.isEmpty {
                            Text("Paste any link — SoundCloud, YouTube, Instagram, TikTok")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 8)
                        }
                        TextField("", text: $urlText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .onChange(of: urlText) { _, val in
                                detectedPlatform = Platform.detect(from: val)
                            }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                detectedPlatform?.color.opacity(0.5) ?? Color.clear,
                                lineWidth: 2
                            )
                    )
                    .onSubmit { startDownload() }

                    Button {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            urlText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Paste from clipboard")

                    Button("Download") { startDownload() }
                        .buttonStyle(.borderedProminent)
                        .tint(detectedPlatform?.color ?? .accentColor)
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(spacing: 16) {
                    if let p = detectedPlatform {
                        HStack(spacing: 4) {
                            Image(systemName: p.icon)
                                .font(.caption)
                            Text(p.rawValue)
                                .font(.caption.bold())
                        }
                        .foregroundStyle(p.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(p.color.opacity(0.12), in: Capsule())
                    }

                    Toggle("Import to Music", isOn: $importToMusic)
                        .toggleStyle(.checkbox)
                        .font(.caption)

                    Spacer()

                    if manager.items.contains(where: { $0.status == .done }) {
                        Button("Clear Completed") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                manager.clearCompleted()
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(16)

            Divider()

            if manager.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("Paste any music link to get started")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        ForEach(Platform.allCases) { p in
                            HStack(spacing: 4) {
                                Image(systemName: p.icon)
                                    .font(.caption2)
                                Text(p.rawValue)
                                    .font(.caption2)
                            }
                            .foregroundStyle(p.color.opacity(0.7))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(manager.items) { item in
                            DownloadRow(item: item, onEdit: { editingItem = item })
                                .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    .padding(8)
                }
            }

            StatusBar()
        }
        .sheet(item: $editingItem) { item in
            MetadataEditor(item: item)
                .environment(manager)
        }
    }

    private func startDownload() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        guard Platform.detect(from: url) != nil else {
            withAnimation {
                errorMessage = "Unrecognized link — paste a SoundCloud, YouTube, Instagram, or TikTok URL"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { errorMessage = nil }
            }
            return
        }

        errorMessage = nil
        urlText = ""
        detectedPlatform = nil
        Task {
            await manager.submitURL(url, importToMusic: importToMusic)
        }
    }
}

// MARK: - Download Row

struct DownloadRow: View {
    let item: DownloadItem
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(item.platform.color)
                .frame(width: 4, height: 36)

            statusIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !item.displayArtist.isEmpty {
                        Text(item.displayArtist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if case .failed(let msg) = item.status {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if item.status != .done {
                        Text(item.status.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if item.status == .downloading {
                ProgressView(value: item.progress)
                    .frame(width: 80)
                    .tint(item.platform.color)
                Text("\(Int(item.progress * 100))%")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            if item.status == .done || item.status == .ready {
                Button { onEdit() } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Edit metadata")
            }

            if let path = item.filePath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([path])
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .fetchingInfo, .downloading, .converting:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.blue)
        case .importing:
            Image(systemName: "music.note")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var rowBackground: some ShapeStyle {
        switch item.status {
        case .done: AnyShapeStyle(Color.green.opacity(0.04))
        case .failed: AnyShapeStyle(Color.red.opacity(0.04))
        default: AnyShapeStyle(Color.clear)
        }
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @Environment(DownloadManager.self) private var manager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(manager.downloadDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button("Open") {
                NSWorkspace.shared.open(manager.downloadDir)
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Spacer()

            if manager.isInstalling {
                ProgressView()
                    .controlSize(.mini)
                Text(manager.installOutput)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Update yt-dlp") {
                    Task { await manager.updateYTDLP() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
