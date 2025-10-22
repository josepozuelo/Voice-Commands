import Foundation

class DictationHistoryStorage {
    private let fileManager = FileManager.default

    private var historyDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceControl/History")
    }

    private var audioDirectory: URL {
        historyDirectory.appendingPathComponent("audio")
    }

    private var historyFileURL: URL {
        historyDirectory.appendingPathComponent("history.json")
    }

    init() {
        setupDirectories()
    }

    // MARK: - Setup

    private func setupDirectories() {
        do {
            try fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            print("📁 DictationHistoryStorage: Directories created at \(historyDirectory.path)")
        } catch {
            print("❌ DictationHistoryStorage: Failed to create directories: \(error)")
        }
    }

    // MARK: - Save

    func saveEntry(transcribedText: String,
                   audioData: Data,
                   duration: TimeInterval,
                   formattedText: String?) throws -> DictationHistoryEntry {

        let entry = DictationHistoryEntry(
            transcribedText: transcribedText,
            audioFileName: "\(UUID().uuidString).wav",
            formattedText: formattedText,
            duration: duration
        )

        // Save audio file
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        try audioData.write(to: audioURL)

        // Load existing entries
        var entries = try loadHistory()

        // Add new entry at the beginning (most recent first)
        entries.insert(entry, at: 0)

        // Enforce max entries limit
        if entries.count > Config.History.maxEntries {
            let entriesToRemove = entries.suffix(from: Config.History.maxEntries)
            for oldEntry in entriesToRemove {
                try? deleteAudioFile(for: oldEntry)
            }
            entries = Array(entries.prefix(Config.History.maxEntries))
        }

        // Save updated entries
        try saveHistory(entries)

        print("💾 DictationHistoryStorage: Saved entry with \(transcribedText.count) chars, audio: \(entry.audioFileName)")

        return entry
    }

    // MARK: - Load

    func loadHistory() throws -> [DictationHistoryEntry] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: historyFileURL)
        let entries = try JSONDecoder().decode([DictationHistoryEntry].self, from: data)
        return entries
    }

    func getAudioData(for entry: DictationHistoryEntry) throws -> Data {
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        return try Data(contentsOf: audioURL)
    }

    // MARK: - Delete

    func deleteEntry(_ entry: DictationHistoryEntry) throws {
        // Load existing entries
        var entries = try loadHistory()

        // Remove the entry
        entries.removeAll { $0.id == entry.id }

        // Delete audio file
        try deleteAudioFile(for: entry)

        // Save updated entries
        try saveHistory(entries)

        print("🗑️ DictationHistoryStorage: Deleted entry \(entry.id)")
    }

    func clearAll() throws {
        // Delete all audio files
        let entries = try loadHistory()
        for entry in entries {
            try? deleteAudioFile(for: entry)
        }

        // Clear history file
        try saveHistory([])

        print("🗑️ DictationHistoryStorage: Cleared all history")
    }

    // MARK: - Private Helpers

    private func saveHistory(_ entries: [DictationHistoryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: historyFileURL)
    }

    private func deleteAudioFile(for entry: DictationHistoryEntry) throws {
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        if fileManager.fileExists(atPath: audioURL.path) {
            try fileManager.removeItem(at: audioURL)
        }
    }
}
