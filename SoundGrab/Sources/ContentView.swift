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
    @State private var preview: TrackPreview?
    @State private var isFetchingPreview = false
    @State private var previewTitle = ""
    @State private var previewArtist = ""
    @State private var fetchID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    TextField(
                        "Paste any link — SoundCloud, YouTube, Instagram, TikTok",
                        text: $urlText
                    )
                    .textFieldStyle(.roundedBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(
                                detectedPlatform?.color.opacity(0.6) ?? Color.clear,
                                lineWidth: 2
                            )
                    )
                    .onChange(of: urlText) { _, val in
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        detectedPlatform = Platform.detect(from: trimmed)
                        if detectedPlatform != nil && looksLikeURL(trimmed) {
                            triggerPreviewFetch(trimmed)
                        } else {
                            preview = nil
                            isFetchingPreview = false
                        }
                    }
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
                }

                if let p = preview, !isFetchingPreview {
                    PreviewCard(
                        preview: p,
                        title: $previewTitle,
                        artist: $previewArtist,
                        importToMusic: $importToMusic,
                        onDownload: { startDownload() },
                        onDismiss: { dismissPreview() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else if isFetchingPreview {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Fetching track info...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 16) {
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

            if manager.items.isEmpty && preview == nil && !isFetchingPreview {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("Paste any music link to get started")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Cmd+V or use the paste button")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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

    private func looksLikeURL(_ text: String) -> Bool {
        text.contains("http://") || text.contains("https://") || text.contains("www.")
    }

    private func triggerPreviewFetch(_ url: String) {
        let thisID = UUID()
        fetchID = thisID
        isFetchingPreview = true
        preview = nil

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard fetchID == thisID else { return }

            if let p = await manager.fetchPreview(url) {
                guard fetchID == thisID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    preview = p
                    previewTitle = p.title
                    previewArtist = p.artist
                    isFetchingPreview = false
                }
            } else {
                guard fetchID == thisID else { return }
                isFetchingPreview = false
            }
        }
    }

    private func dismissPreview() {
        withAnimation(.easeInOut(duration: 0.15)) {
            preview = nil
            urlText = ""
            detectedPlatform = nil
            previewTitle = ""
            previewArtist = ""
        }
    }

    private func startDownload() {
        let url: String
        let editedTitle: String?
        let editedArtist: String?

        if let p = preview {
            url = p.url
            editedTitle = previewTitle != p.title ? previewTitle : nil
            editedArtist = previewArtist != p.artist ? previewArtist : nil
        } else {
            url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            editedTitle = nil
            editedArtist = nil
        }

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
        let doImport = importToMusic

        withAnimation(.easeInOut(duration: 0.15)) {
            preview = nil
            urlText = ""
            detectedPlatform = nil
            previewTitle = ""
            previewArtist = ""
        }

        Task {
            await manager.submitURL(url, importToMusic: doImport, editedTitle: editedTitle, editedArtist: editedArtist)
        }
    }
}

// MARK: - Preview Card

struct PreviewCard: View {
    let preview: TrackPreview
    @Binding var title: String
    @Binding var artist: String
    @Binding var importToMusic: Bool
    var onDownload: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let data = preview.thumbnailData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(preview.platform.color.opacity(0.15))
                        Image(systemName: preview.platform.icon)
                            .font(.title2)
                            .foregroundStyle(preview.platform.color)
                    }
                    .frame(width: 64, height: 64)
                }

                if preview.isPlaylist {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "music.note.list")
                                .font(.caption)
                            Text("Playlist — \(preview.trackCount) tracks")
                                .font(.body.bold())
                        }
                        .foregroundStyle(preview.platform.color)

                        Text("All tracks will be downloaded as 320kbps MP3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)

                        HStack(spacing: 8) {
                            TextField("Artist", text: $artist)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)

                            if let dur = preview.durationText {
                                Text(dur)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .frame(minWidth: 36)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            Divider()
                .padding(.vertical, 10)

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: preview.platform.icon)
                        .font(.caption2)
                    Text(preview.platform.rawValue)
                        .font(.caption.bold())
                }
                .foregroundStyle(preview.platform.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(preview.platform.color.opacity(0.12), in: Capsule())

                Toggle("Import to Music", isOn: $importToMusic)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()

                Button("Cancel") { onDismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button(preview.isPlaylist ? "Download All" : "Download") { onDownload() }
                    .buttonStyle(.borderedProminent)
                    .tint(preview.platform.color)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(preview.platform.color.opacity(0.2), lineWidth: 1)
        )
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
