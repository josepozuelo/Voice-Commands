# VoiceControl - Voice Command App

A powerful voice-controlled text manipulation app for macOS that enables hands-free text selection, navigation, and system commands.

## Features

### Voice Commands
- **Text Selection**: Select words, sentences, paragraphs, and more
- **Smart Selection**: Select last word, sentence, or paragraph
- **Navigation**: Move cursor by word, line, or document
- **System Commands**: Copy, paste, cut, undo, redo, save, find
- **Window Management**: Switch windows, change tabs

### Key Capabilities
- **Fuzzy Matching**: Intelligent command recognition with confidence scoring
- **Auto-Choose**: Execute high-confidence commands immediately
- **Disambiguation HUD**: Visual picker for low-confidence matches
- **Text Selection Mechanics**: Advanced text boundary detection
- **Global Hotkeys**: System-wide activation with ⌥⌘C

## Setup Instructions

### Prerequisites
1. **macOS 13.0+** (Ventura or later)
2. **Xcode 15.0+** 
3. **OpenAI API Key** for speech recognition

### Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd VoiceControl
   ```

2. **Set up OpenAI API Key**:
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```
   
   Add this to your `~/.zshrc` or `~/.bash_profile` for persistence.

3. **Open in Xcode**:
   ```bash
   open VoiceControl.xcodeproj
   ```

4. **Build and Run**:
   - Select your development team in signing settings
   - Build and run the project (⌘R)

### Required Permissions

The app will request the following permissions on first run:

1. **Microphone Access**: For voice command recognition
2. **Accessibility Access**: For text manipulation and cursor control
3. **Input Monitoring**: For global hotkey detection

Grant these permissions in **System Settings > Privacy & Security**.

## Usage

### Basic Commands

1. **Activate Voice Commands**: Press `⌥⌘C` (Option+Command+C)
2. **Speak a command**: e.g., "select word", "copy", "select last sentence"
3. **Command executes automatically** if confidence is high
4. **Choose from options** if multiple matches are found

### Available Commands

#### Text Selection
- "select word" - Select current word
- "select last word" - Select previous word
- "select sentence" - Select current sentence
- "select last sentence" - Select previous sentence  
- "select paragraph" - Select current paragraph
- "select last paragraph" - Select previous paragraph
- "select all" - Select entire document
- "select line" - Select current line

#### System Commands
- "copy" - Copy selection (⌘C)
- "paste" - Paste clipboard (⌘V)
- "cut" - Cut selection (⌘X)
- "undo" - Undo last action (⌘Z)
- "redo" - Redo last action (⌘⇧Z)
- "save" - Save document (⌘S)
- "find" - Open find dialog (⌘F)

#### Navigation
- "go to end" - Move to end of document
- "go to beginning" - Move to start of document
- "next word" - Move to next word
- "previous word" - Move to previous word

#### Window Management
- "switch window" - Switch between app windows
- "next tab" - Switch to next tab
- "previous tab" - Switch to previous tab

### Hotkeys

- **⌥⌘C**: Voice Commands (implemented)
- **⌥⌘D**: Dictation Mode (future)
- **⌥⌘E**: Edit Mode (future)

## Architecture

### Core Components

- **AudioEngine**: Microphone capture and audio processing
- **WhisperService**: OpenAI Whisper integration for speech-to-text
- **AccessibilityBridge**: Text manipulation via macOS Accessibility APIs
- **CommandMatcher**: Fuzzy matching algorithm for command recognition
- **CommandManager**: Workflow orchestration and state management
- **CommandHUD**: Visual feedback and disambiguation interface

### Project Structure

```
VoiceControl/
├── VoiceControlApp.swift          # Main app entry
├── Config/
│   └── Config.swift              # Centralized configuration
├── Core/
│   ├── AudioEngine.swift         # Mic capture & processing
│   ├── WhisperService.swift      # OpenAI Whisper integration
│   └── AccessibilityBridge.swift # Text manipulation via AXUIElement
├── Features/
│   └── Command/
│       ├── CommandManager.swift  # Command workflow orchestration
│       ├── CommandMatcher.swift  # Fuzzy matching engine
│       └── CommandHUD.swift      # Visual interface
├── Models/
│   └── Command.swift            # Command data structures
├── Resources/
│   └── commands.json            # Command definitions
└── Utils/
    ├── HotkeyManager.swift      # Global hotkey handling
    └── TextSelection.swift      # Text selection utilities
```

## Troubleshooting

### Common Issues

1. **"No API Key" error**: Ensure `OPENAI_API_KEY` environment variable is set
2. **Commands not working**: Check Accessibility permissions in System Settings
3. **Hotkey not detected**: Verify Input Monitoring permissions
4. **No microphone access**: Check Microphone permissions

### Testing Commands

Test with these common applications:
- TextEdit
- Safari
- VS Code
- Xcode
- Notes

## Development

### Adding New Commands

1. Edit `Resources/commands.json`
2. Add new command with phrases and actions
3. Rebuild and test

### Extending Functionality

- **New Action Types**: Extend `CommandAction` enum
- **Custom Selection Types**: Add to `SelectionType` enum  
- **App-Specific Commands**: Implement in `AccessibilityBridge`

## Future Enhancements

- Dictation Mode for continuous speech-to-text
- Edit Mode with AI-powered text transformations
- Custom command creation UI
- Offline speech recognition
- Multi-language support

## License

MIT License - see LICENSE file for details.