# Highlight Phrase Feature Design

## Overview
Enable users to select specific words or phrases in their text by speaking them. For example, saying "highlight the word example" or "select the phrase hello world" will find and select that exact text in the current context.

## User Flow
1. User activates voice command (Control+Shift+V)
2. User says "highlight [phrase]" or "select the phrase [phrase]"
3. System transcribes the speech
4. LLM extracts the target phrase from the command
5. System finds and highlights the phrase in the current text context

## Technical Design

### 1. LLM Intent Update
Add a new intent `highlight_phrase` to the CommandJSON structure:

```swift
enum CommandIntent: String, Codable {
    // existing intents...
    case highlight_phrase = "highlight_phrase"
}
```

Update the LLM prompt to recognize this intent and extract the target phrase:
- Input: "highlight the word example"
- Output: `{"intent": "highlight_phrase", "phrase": "example"}`

### 2. CommandJSON Model Update
Add phrase field to CommandJSON:

```swift
struct CommandJSON: Codable {
    // existing fields...
    let phrase: String?  // For highlight_phrase intent
}
```

### 3. AccessibilityBridge Enhancement
Add new method to find and select text:

```swift
func selectPhrase(_ targetPhrase: String) throws {
    // 1. Get current text context (paragraph or visible text)
    let context = try getEditContext()
    
    // 2. Find phrase location in context
    let range = findPhraseInContext(targetPhrase, context)
    
    // 3. Navigate to and select the phrase
    try navigateAndSelect(range, in: context)
}
```

Key implementation details:
- Use existing `getEditContext()` to get surrounding text
- Search for exact phrase match (case-insensitive option)
- Handle multiple occurrences (select nearest to cursor)
- Use keyboard navigation to select the found text

### 4. CommandRouter Update
Add routing for highlight_phrase:

```swift
case .highlight_phrase:
    try await routeHighlightPhrase(command)

private func routeHighlightPhrase(_ command: CommandJSON) async throws {
    guard let phrase = command.phrase else {
        throw RouteError.missingParameters("Highlight phrase requires phrase")
    }
    
    try accessibilityBridge.selectPhrase(phrase)
}
```

## Implementation Steps

### Phase 1: LLM Integration
1. Update GPT prompt template to recognize highlight_phrase intent
2. Add phrase extraction logic to identify target text
3. Test LLM response accuracy with various phrasings

### Phase 2: Accessibility Implementation
1. Implement `findPhraseInContext()` method
   - Text search algorithm
   - Handle edge cases (phrase at boundaries)
   - Multiple occurrence resolution
2. Implement `navigateAndSelect()` method
   - Calculate cursor movements needed
   - Use existing selection commands
   - Verify selection accuracy

### Phase 3: Integration & Testing
1. Wire up CommandRouter with new intent
2. Add visual feedback in CommandHUD
3. Handle error cases (phrase not found)
4. Test with various applications

## Challenges & Solutions

### Challenge 1: Getting Text Context
- **Issue**: Limited access to full document text via Accessibility API
- **Solution**: Use paragraph-level context initially, with option to expand search

### Challenge 2: Precise Selection
- **Issue**: Navigating to exact text position
- **Solution**: Combine word-by-word navigation with selection verification

### Challenge 3: Multiple Occurrences
- **Issue**: Same phrase appears multiple times
- **Solution**: 
  - Select nearest to cursor position
  - Future: Add disambiguation ("the second one", "next occurrence")

### Challenge 4: Performance
- **Issue**: Large documents may be slow to search
- **Solution**: 
  - Limit initial search to visible/nearby text
  - Implement progressive search expansion

## Example Usage
- "highlight the word configuration"
- "select John Smith"
- "highlight the phrase to be or not to be"
- "select the URL"

## Future Enhancements
1. Support for partial matches and fuzzy search
2. Regular expression support ("highlight email addresses")
3. Multiple selection ("highlight all instances of TODO")
4. Context-aware selection ("highlight the function name")
5. Voice-based disambiguation for multiple matches

## Success Metrics
- Phrase found and selected correctly in 95%+ of cases
- Response time under 1 second for typical documents
- Works across all text-editable applications
- Clear error messages when phrase not found