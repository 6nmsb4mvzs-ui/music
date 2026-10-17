import SwiftUI
import UniformTypeIdentifiers

struct MetadataEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var manager
    let item: DownloadItem

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var coverImage: NSImage?
    @State private var newCoverData: Data?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Track Info")
                .font(.title3.bold())

            HStack(spacing: 20) {
                coverView
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary)
                            .allowsHitTesting(false)
                    )
                    .onTapGesture { pickImage() }

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NativeTextField(placeholder: "Track title", text: $title)
                            .frame(height: 24)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NativeTextField(placeholder: "Artist name", text: $artist)
                            .frame(height: 24)
                    }

                    Button("Change Cover Art") { pickImage() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            HStack(spacing: 8) {
                if let p = item.filePath {
                    HStack(spacing: 4) {
                        Image(systemName: item.platform.icon)
                            .font(.caption2)
                        Text(p.lastPathComponent)
                            .font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }

            if isSaving {
                ProgressView("Applying changes...")
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            title = item.displayTitle
            artist = item.displayArtist
            if let data = item.coverData, let img = NSImage(data: data) {
                coverImage = img
            }
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if let img = coverImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Click to add")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select cover art image"

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                coverImage = img
                newCoverData = data
            }
        }
    }

    private func save() {
        isSaving = true

        let editedTitle = title != item.title ? title : nil
        let editedArtist = artist != item.artist ? artist : nil

        item.editedTitle = editedTitle ?? item.editedTitle
        item.editedArtist = editedArtist ?? item.editedArtist
        if let data = newCoverData {
            item.editedCover = data
            item.coverData = data
        }

        guard let filePath = item.filePath, let ffmpeg = manager.ffmpegPath else {
            isSaving = false
            dismiss()
            return
        }

        Task {
            if editedTitle != nil || editedArtist != nil {
                let _ = await MetadataService.applyMetadata(
                    title: editedTitle, artist: editedArtist,
                    to: filePath, ffmpegPath: ffmpeg
                )
            }

            if let data = newCoverData {
                let _ = await MetadataService.applyCoverArt(data, to: filePath, ffmpegPath: ffmpeg)
            }

            await MainActor.run {
                if let t = editedTitle { item.title = t }
                if let a = editedArtist { item.artist = a }
                isSaving = false
                dismiss()
            }
        }
    }
}
