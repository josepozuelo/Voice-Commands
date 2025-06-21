import Foundation

struct TextSelection {
    let text: String
    let range: NSRange
    let position: Int
}

class TextSelectionUtils {
    
    static func findWordBoundaries(in text: String, at position: Int) -> NSRange? {
        guard position >= 0 && position <= text.count else { return nil }
        
        let nsString = text as NSString
        let options: NSString.EnumerationOptions = [.byWords, .localized]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length),
                                   options: options) { _, range, _, stop in
            if range.contains(position) || (position == range.location + range.length) {
                result = range
                stop.pointee = true
            }
        }
        
        return result
    }
    
    static func findSentenceBoundaries(in text: String, at position: Int) -> NSRange? {
        guard position >= 0 && position <= text.count else { return nil }
        
        let nsString = text as NSString
        let options: NSString.EnumerationOptions = [.bySentences, .localized]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length),
                                   options: options) { _, range, _, stop in
            if range.contains(position) || (position == range.location + range.length) {
                result = range
                stop.pointee = true
            }
        }
        
        return result
    }
    
    static func findParagraphBoundaries(in text: String, at position: Int) -> NSRange? {
        guard position >= 0 && position <= text.count else { return nil }
        
        let nsString = text as NSString
        let options: NSString.EnumerationOptions = [.byParagraphs, .localized]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length),
                                   options: options) { _, range, _, stop in
            if range.contains(position) || (position == range.location + range.length) {
                result = range
                stop.pointee = true
            }
        }
        
        return result
    }
    
    static func findLineBoundaries(in text: String, at position: Int) -> NSRange? {
        guard position >= 0 && position <= text.count else { return nil }
        
        let nsString = text as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: position, length: 0))
        
        return lineRange
    }
    
    static func findLastWord(in text: String, before position: Int) -> NSRange? {
        guard position > 0 && position <= text.count else { return nil }
        
        let nsString = text as NSString
        let searchRange = NSRange(location: 0, length: position)
        let options: NSString.EnumerationOptions = [.byWords, .localized, .reverse]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: searchRange, options: options) { _, range, _, stop in
            result = range
            stop.pointee = true
        }
        
        return result
    }
    
    static func findLastSentence(in text: String, before position: Int) -> NSRange? {
        guard position > 0 && position <= text.count else { return nil }
        
        let nsString = text as NSString
        let searchRange = NSRange(location: 0, length: position)
        let options: NSString.EnumerationOptions = [.bySentences, .localized, .reverse]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: searchRange, options: options) { _, range, _, stop in
            result = range
            stop.pointee = true
        }
        
        return result
    }
    
    static func findLastParagraph(in text: String, before position: Int) -> NSRange? {
        guard position > 0 && position <= text.count else { return nil }
        
        let nsString = text as NSString
        let searchRange = NSRange(location: 0, length: position)
        let options: NSString.EnumerationOptions = [.byParagraphs, .localized, .reverse]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: searchRange, options: options) { _, range, _, stop in
            result = range
            stop.pointee = true
        }
        
        return result
    }
    
    static func findNextWord(in text: String, after position: Int) -> NSRange? {
        guard position >= 0 && position < text.count else { return nil }
        
        let nsString = text as NSString
        let searchRange = NSRange(location: position, length: nsString.length - position)
        let options: NSString.EnumerationOptions = [.byWords, .localized]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: searchRange, options: options) { _, range, _, stop in
            if range.location > position {
                result = range
                stop.pointee = true
            }
        }
        
        return result
    }
    
    static func findNextSentence(in text: String, after position: Int) -> NSRange? {
        guard position >= 0 && position < text.count else { return nil }
        
        let nsString = text as NSString
        let searchRange = NSRange(location: position, length: nsString.length - position)
        let options: NSString.EnumerationOptions = [.bySentences, .localized]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: searchRange, options: options) { _, range, _, stop in
            if range.location > position {
                result = range
                stop.pointee = true
            }
        }
        
        return result
    }
    
    static func findNextParagraph(in text: String, after position: Int) -> NSRange? {
        guard position >= 0 && position < text.count else { return nil }
        
        let nsString = text as NSString
        let searchRange = NSRange(location: position, length: nsString.length - position)
        let options: NSString.EnumerationOptions = [.byParagraphs, .localized]
        var result: NSRange?
        
        nsString.enumerateSubstrings(in: searchRange, options: options) { _, range, _, stop in
            if range.location > position {
                result = range
                stop.pointee = true
            }
        }
        
        return result
    }
    
    static func getSelectionForType(_ selectionType: SelectionType, in text: String, at position: Int) -> NSRange? {
        switch selectionType {
        case .word:
            return findWordBoundaries(in: text, at: position)
        case .sentence:
            return findSentenceBoundaries(in: text, at: position)
        case .paragraph:
            return findParagraphBoundaries(in: text, at: position)
        case .line:
            return findLineBoundaries(in: text, at: position)
        case .all:
            return NSRange(location: 0, length: text.count)
        case .lastWord:
            return findLastWord(in: text, before: position)
        case .lastSentence:
            return findLastSentence(in: text, before: position)
        case .lastParagraph:
            return findLastParagraph(in: text, before: position)
        case .nextWord:
            return findNextWord(in: text, after: position)
        case .nextSentence:
            return findNextSentence(in: text, after: position)
        case .nextParagraph:
            return findNextParagraph(in: text, after: position)
        case .toEndOfLine:
            let lineRange = findLineBoundaries(in: text, at: position)
            return lineRange.map { NSRange(location: position, length: $0.location + $0.length - position) }
        case .toStartOfLine:
            let lineRange = findLineBoundaries(in: text, at: position)
            return lineRange.map { NSRange(location: $0.location, length: position - $0.location) }
        case .toEndOfDocument:
            return NSRange(location: position, length: text.count - position)
        case .toStartOfDocument:
            return NSRange(location: 0, length: position)
        default:
            return nil
        }
    }
    
    static func isWordSeparator(_ character: Character) -> Bool {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return character.unicodeScalars.allSatisfy { separators.contains($0) }
    }
    
    static func isSentenceEnder(_ character: Character) -> Bool {
        return character == "." || character == "!" || character == "?"
    }
    
    static func isParagraphSeparator(_ character: Character) -> Bool {
        return character == "\n" || character == "\r"
    }
}