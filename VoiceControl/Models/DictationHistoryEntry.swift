import Foundation

struct DictationHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let transcribedText: String
    let audioFileName: String
    let formattedText: String?
    let duration: TimeInterval

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         transcribedText: String,
         audioFileName: String,
         formattedText: String?,
         duration: TimeInterval) {
        self.id = id
        self.timestamp = timestamp
        self.transcribedText = transcribedText
        self.audioFileName = audioFileName
        self.formattedText = formattedText
        self.duration = duration
    }

    var displayText: String {
        formattedText ?? transcribedText
    }
}
