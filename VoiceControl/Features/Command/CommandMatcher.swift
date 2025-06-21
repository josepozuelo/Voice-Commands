import Foundation

struct CommandMatch {
    let command: Command
    let confidence: Double
    let matchedPhrase: String
}

class CommandMatcher {
    private let commands: [Command]
    
    init() {
        commands = CommandMatcher.loadCommands()
    }
    
    private static func loadCommands() -> [Command] {
        guard let url = Bundle.main.url(forResource: "commands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let commandList = try? JSONDecoder().decode(CommandList.self, from: data) else {
            print("Failed to load commands.json")
            return []
        }
        
        return commandList.commands
    }
    
    func findMatches(for spokenText: String) -> [CommandMatch] {
        let normalizedInput = normalizeText(spokenText)
        var matches: [CommandMatch] = []
        
        for command in commands {
            var bestMatch: CommandMatch?
            
            for phrase in command.phrases {
                let normalizedPhrase = normalizeText(phrase)
                let confidence = calculateSimilarity(normalizedInput, normalizedPhrase)
                
                if confidence > 0.3 {
                    if bestMatch == nil || confidence > bestMatch!.confidence {
                        bestMatch = CommandMatch(
                            command: command,
                            confidence: confidence,
                            matchedPhrase: phrase
                        )
                    }
                }
            }
            
            if let match = bestMatch {
                matches.append(match)
            }
        }
        
        return matches.sorted { $0.confidence > $1.confidence }
    }
    
    func getBestMatch(for spokenText: String) -> CommandMatch? {
        let matches = findMatches(for: spokenText)
        return matches.first
    }
    
    func shouldShowDisambiguation(for spokenText: String) -> Bool {
        let matches = findMatches(for: spokenText)
        
        guard let bestMatch = matches.first else { return false }
        
        if bestMatch.confidence < Config.fuzzyMatchThreshold {
            return matches.count > 1
        }
        
        return false
    }
    
    private func normalizeText(_ text: String) -> String {
        return text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
    
    private func calculateSimilarity(_ text1: String, _ text2: String) -> Double {
        if text1 == text2 {
            return 1.0
        }
        
        if text1.isEmpty || text2.isEmpty {
            return 0.0
        }
        
        if text1.contains(text2) || text2.contains(text1) {
            return 0.9
        }
        
        let distance = levenshteinDistance(text1, text2)
        let maxLength = max(text1.count, text2.count)
        
        if maxLength == 0 {
            return 1.0
        }
        
        let normalizedDistance = Double(distance) / Double(maxLength)
        let similarity = 1.0 - normalizedDistance
        
        let words1 = Set(text1.split(separator: " ").map(String.init))
        let words2 = Set(text2.split(separator: " ").map(String.init))
        let commonWords = words1.intersection(words2)
        let totalWords = words1.union(words2)
        
        let wordSimilarity = totalWords.isEmpty ? 0.0 : Double(commonWords.count) / Double(totalWords.count)
        
        return (similarity * 0.7) + (wordSimilarity * 0.3)
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        
        var distances = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count {
            distances[i][0] = i
        }
        
        for j in 0...b.count {
            distances[0][j] = j
        }
        
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    distances[i][j] = distances[i - 1][j - 1]
                } else {
                    distances[i][j] = min(
                        distances[i - 1][j] + 1,
                        distances[i][j - 1] + 1,
                        distances[i - 1][j - 1] + 1
                    )
                }
            }
        }
        
        return distances[a.count][b.count]
    }
    
    func getTopMatches(for spokenText: String, limit: Int = 3) -> [CommandMatch] {
        let matches = findMatches(for: spokenText)
        return Array(matches.prefix(limit))
    }
}