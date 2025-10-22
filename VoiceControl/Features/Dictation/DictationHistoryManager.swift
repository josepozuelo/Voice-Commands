import Foundation
import AVFoundation
import Combine

@MainActor
class DictationHistoryManager: ObservableObject {
    @Published var entries: [DictationHistoryEntry] = []
    @Published var searchText: String = ""
    @Published var currentlyPlayingId: UUID?
    @Published var errorMessage: String?

    private let storage = DictationHistoryStorage()
    private var audioPlayer: AVAudioPlayer?

    // Computed property for filtered entries based on search
    var filteredEntries: [DictationHistoryEntry] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter { entry in
            entry.displayText.localizedCaseInsensitiveContains(searchText)
        }
    }

    init() {
        loadHistory()
    }

    // MARK: - Load

    func loadHistory() {
        do {
            entries = try storage.loadHistory()
            print("📖 DictationHistoryManager: Loaded \(entries.count) entries")
        } catch {
            print("❌ DictationHistoryManager: Failed to load history: \(error)")
            errorMessage = "Failed to load history: \(error.localizedDescription)"
            entries = []
        }
    }

    // MARK: - Save

    func saveEntry(transcribedText: String,
                   audioData: Data,
                   duration: TimeInterval,
                   formattedText: String?) {
        do {
            let entry = try storage.saveEntry(
                transcribedText: transcribedText,
                audioData: audioData,
                duration: duration,
                formattedText: formattedText
            )

            // Insert at the beginning (most recent first)
            entries.insert(entry, at: 0)

            // Enforce max entries limit
            if entries.count > Config.History.maxEntries {
                entries = Array(entries.prefix(Config.History.maxEntries))
            }

            print("💾 DictationHistoryManager: Entry saved successfully")
        } catch {
            print("❌ DictationHistoryManager: Failed to save entry: \(error)")
            errorMessage = "Failed to save entry: \(error.localizedDescription)"
        }
    }

    // MARK: - Playback

    func playEntry(_ entry: DictationHistoryEntry) {
        // If already playing this entry, stop it
        if currentlyPlayingId == entry.id {
            stopPlayback()
            return
        }

        // Stop any currently playing audio
        stopPlayback()

        do {
            let audioData = try storage.getAudioData(for: entry)

            // Create a temporary file for the audio player
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(entry.id).wav")
            try audioData.write(to: tempURL)

            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = AudioPlayerDelegate(onFinish: { [weak self] in
                DispatchQueue.main.async {
                    self?.currentlyPlayingId = nil
                }
            })

            audioPlayer?.play()
            currentlyPlayingId = entry.id

            print("🔊 DictationHistoryManager: Playing entry \(entry.id)")
        } catch {
            print("❌ DictationHistoryManager: Failed to play audio: \(error)")
            errorMessage = "Failed to play audio: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingId = nil
    }

    // MARK: - Delete

    func deleteEntry(_ entry: DictationHistoryEntry) {
        do {
            // Stop playback if this entry is currently playing
            if currentlyPlayingId == entry.id {
                stopPlayback()
            }

            try storage.deleteEntry(entry)
            entries.removeAll { $0.id == entry.id }

            print("🗑️ DictationHistoryManager: Entry deleted")
        } catch {
            print("❌ DictationHistoryManager: Failed to delete entry: \(error)")
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
        }
    }

    func clearAll() {
        do {
            stopPlayback()
            try storage.clearAll()
            entries = []
            print("🗑️ DictationHistoryManager: All entries cleared")
        } catch {
            print("❌ DictationHistoryManager: Failed to clear history: \(error)")
            errorMessage = "Failed to clear history: \(error.localizedDescription)"
        }
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Audio Player Delegate

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
