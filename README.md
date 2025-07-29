# VoiceControl

A macOS app for hands-free text manipulation through voice commands and dictation.

## Quick Start

⚠️ **Important**: Always open `VoiceControl.xcworkspace` in Xcode, NOT the `.xcodeproj` file. The workspace includes necessary dependencies.

## Features

- **Voice Commands**: Control text selection, navigation, and system functions
- **Dictation Mode**: Long-form speech-to-text input
- **Edit Mode**: Voice-controlled text transformations
- **Continuous Mode**: Chain multiple commands without reactivating
- **Smart Disambiguation**: Visual picker for similar commands

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
   open VoiceControl.xcworkspace
   ```
   
   ⚠️ **Must use the `.xcworkspace` file, not `.xcodeproj`**

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

### Keyboard Shortcuts

- **⌃⇧V**: Voice Commands
- **⌃⇧D**: Dictation Mode
- **⌃⇧E**: Edit Mode

### Voice Commands Mode

Press **⌃⇧V** (Control+Shift+V) and speak a command:

**Text Selection**
- "select word/sentence/paragraph/line/all"
- "select last word/sentence/paragraph"

**System Commands**
- "copy", "paste", "cut"
- "undo", "redo"
- "save", "find"

**Navigation**
- "go to beginning/end"
- "next/previous word"

**Window Management**
- "switch window"
- "next/previous tab"

### Dictation Mode

Press **⌃⇧D** (Control+Shift+D) to start continuous speech-to-text input. Speak naturally and your words will be typed at the cursor position.

### Edit Mode

Press **⌃⇧E** (Control+Shift+E) to transform selected text using voice commands:
- "make this uppercase/lowercase"
- "fix grammar"
- "make it formal/casual"


## Troubleshooting

1. **"No API Key" error**: Set `OPENAI_API_KEY` environment variable
2. **Commands not working**: Check Accessibility permissions
3. **Hotkey not detected**: Verify Input Monitoring permissions
4. **No microphone access**: Check Microphone permissions

## License

MIT License