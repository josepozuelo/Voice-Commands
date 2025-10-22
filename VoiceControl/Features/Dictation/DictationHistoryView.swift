import SwiftUI

struct DictationHistoryView: View {
    @EnvironmentObject var historyManager: DictationHistoryManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if historyManager.filteredEntries.isEmpty {
                emptyStateView
            } else {
                historyListView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .alert(isPresented: .constant(historyManager.errorMessage != nil)) {
            Alert(
                title: Text("Error"),
                message: Text(historyManager.errorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK")) {
                    historyManager.clearError()
                }
            )
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                Text("Dictation History")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(historyManager.filteredEntries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search transcriptions...", text: $historyManager.searchText)
                    .textFieldStyle(.plain)

                if !historyManager.searchText.isEmpty {
                    Button(action: {
                        historyManager.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Action buttons
            HStack {
                Button(action: {
                    historyManager.loadHistory()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Spacer()

                if !historyManager.entries.isEmpty {
                    Button(role: .destructive, action: {
                        showClearConfirmation()
                    }) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding()
    }

    // MARK: - List

    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(historyManager.filteredEntries) { entry in
                    HistoryEntryRow(
                        entry: entry,
                        isPlaying: historyManager.currentlyPlayingId == entry.id,
                        onPlay: {
                            historyManager.playEntry(entry)
                        },
                        onDelete: {
                            historyManager.deleteEntry(entry)
                        }
                    )
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(historyManager.searchText.isEmpty ? "No Dictations Yet" : "No Results")
                .font(.title2)
                .fontWeight(.semibold)

            Text(historyManager.searchText.isEmpty ?
                 "Your dictation history will appear here" :
                 "Try a different search term")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func showClearConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Clear All History?"
        alert.informativeText = "This will permanently delete all dictation recordings and cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            historyManager.clearAll()
        }
    }
}

// MARK: - History Entry Row

struct HistoryEntryRow: View {
    let entry: DictationHistoryEntry
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Play button
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(isPlaying ? .red : .accentColor)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Stop playback" : "Play recording")

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Timestamp and duration
                HStack {
                    Text(formatDate(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(formatDuration(entry.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if entry.formattedText != nil {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .help("GPT formatted")
                    }
                }

                // Transcription text
                Text(entry.displayText)
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete entry")
        }
        .padding()
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

struct DictationHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        DictationHistoryView()
            .environmentObject({
                let manager = DictationHistoryManager()
                return manager
            }())
    }
}
