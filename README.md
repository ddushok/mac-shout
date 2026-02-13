# MacShout

> whisper, but louder

A native macOS menu bar application for local, on-device speech-to-text transcription using [whisper.cpp](https://github.com/ggml-org/whisper.cpp). Optimized for Apple Silicon Macs with Metal acceleration.

## Features

- 🎙️ **Push-to-Talk**: Hold a hotkey to record, release to transcribe and insert text into the active app
- 🖥️ **Menu Bar Only**: Lightweight menu bar app that stays out of your way
- 🔒 **Private & Local**: All transcription happens on-device using Metal acceleration
- ⚡ **Fast**: Optimized for Apple Silicon with Metal GPU acceleration
- 🎯 **Multiple Models**: Choose from tiny to large models based on your accuracy needs
- 🎤 **Microphone Selection**: Pick your preferred input device
- ⌨️ **Customizable Hotkey**: Configure your own push-to-talk shortcut

## Requirements

- macOS 13.3 (Ventura) or later
- Apple Silicon Mac (M1, M2, M3, M4, etc.)
- Xcode 15.0+ (for building)
- Homebrew (for dependencies)

## Setup

1. **Clone the repository** (if not already done):
   ```bash
   git clone https://github.com/ddushok/mac-shout.git
   cd mac-shout
   ```

2. **Run the setup script**:
   ```bash
   ./scripts/setup.sh
   ```
   
   This will:
   - Download the whisper.cpp XCFramework (v1.8.3)
   - Create the models directory at `~/Library/Application Support/MacShout/Models`
   - Generate the Xcode project using xcodegen

3. **Open the project in Xcode**:
   ```bash
   open MacShout.xcodeproj
   ```

4. **Select your Development Team**:
   - In Xcode, select the MacShout target
   - Go to "Signing & Capabilities"
   - Select your development team from the dropdown

5. **Build and Run**:
   - Press `Cmd+R` or click the Run button
   - The app will appear in your menu bar (look for the waveform icon)

## First Launch

### 1. Grant Permissions

MacShout requires two permissions:

**Microphone Access** (prompted automatically):
- Required to record audio
- Click "OK" when prompted

**Accessibility Access** (must be granted manually):
- Required for global hotkey detection and text insertion
- Go to System Settings > Privacy & Security > Accessibility
- Click the lock icon and authenticate
- Enable "MacShout" in the list

### 2. Download a Model

1. Click the MacShout icon in the menu bar
2. Click the gear icon to open Settings
3. Click "Download Models"
4. Start with `base.en` (142 MB) - good balance of speed and accuracy
5. Wait for the download to complete

### 3. Configure Your Hotkey

The default hotkey is the **Right Option** key. To change it:

1. Open Settings (gear icon)
2. In the "Push-to-Talk Hotkey" section, click "Change"
3. Press the key you want to use (e.g., F13, Right Command, etc.)

## Usage

1. **Start Recording**: Press and hold your hotkey
   - The menu bar icon changes to a red microphone
   - Speak clearly into your microphone

2. **Stop & Transcribe**: Release the hotkey
   - Recording stops
   - Transcription begins (menu bar shows "Transcribing...")
   - Text is automatically typed into your active application

3. **View Results**: Click the menu bar icon to see:
   - Current status
   - Last transcription (with copy button)
   - Model and hotkey information

## Available Models

| Model | Size | Memory | Best For |
|-------|------|--------|----------|
| **tiny.en** | 75 MB | ~273 MB | Quick drafts, simple commands |
| **base.en** | 142 MB | ~388 MB | **Recommended starter** - good balance |
| **small.en** | 466 MB | ~852 MB | Better accuracy for longer text |
| **medium.en** | 1.5 GB | ~2.1 GB | High accuracy transcription |
| **large-v3-turbo** | 1.5 GB | ~3.9 GB | Best quality, slower |

Models are downloaded to: `~/Library/Application Support/MacShout/Models/`

## Settings

### Model Selection
Choose which Whisper model to use for transcription. Larger models are more accurate but slower.

### Microphone
Select your preferred audio input device. Click "Refresh Devices" if you connect a new microphone.

### Push-to-Talk Hotkey
Customize the key you press to start/stop recording. Good options:
- Right Option (default)
- F13-F18 keys
- Right Command
- Right Control

### Options
- **Auto-transcribe after recording**: Automatically process audio when you release the hotkey
- **Show notifications**: Display a notification with transcribed text

## Troubleshooting

### No audio is recorded
- Check microphone permissions in System Settings > Privacy & Security > Microphone
- Verify correct microphone is selected in MacShout settings
- Test your microphone in another app (like Voice Memos)

### Hotkey not working
- Ensure Accessibility permission is granted
- Check System Settings > Privacy & Security > Accessibility
- MacShout must be enabled in the list
- Try restarting the app after granting permission

### Text not inserting
- Accessibility permission is required
- Make sure the target app is focused before releasing the hotkey
- Some apps (like terminal with secure input) may block text insertion

### Model not downloading
- Check your internet connection
- Verify you have enough disk space
- Models are downloaded from HuggingFace

### Build errors
- Make sure you have Xcode 15.0+
- Run `./scripts/setup.sh` again
- Clean build folder: `rm -rf ~/Library/Developer/Xcode/DerivedData/MacShout-*`

## Development

### Project Structure

```
mac-shout/
├── MacShout/
│   ├── MacShoutApp.swift          # App entry point
│   ├── AppSettings.swift          # Settings management
│   ├── Whisper/
│   │   ├── WhisperContext.swift   # whisper.cpp wrapper
│   │   └── ModelManager.swift     # Model downloads & loading
│   ├── Audio/
│   │   └── AudioRecorder.swift    # Microphone capture
│   ├── Input/
│   │   ├── HotKeyMonitor.swift    # Global hotkey handling
│   │   └── TextInserter.swift     # Text insertion via CGEvent
│   └── Views/
│       ├── MenuBarView.swift      # Main UI
│       └── SettingsView.swift     # Settings UI
├── Frameworks/
│   └── whisper.xcframework/       # Pre-built whisper.cpp
├── project.yml                     # xcodegen configuration
└── scripts/
    └── setup.sh                    # Setup script
```

### Building from Source

```bash
# Install dependencies
brew install xcodegen

# Run setup
./scripts/setup.sh

# Generate project
xcodegen generate

# Build
xcodebuild -project MacShout.xcodeproj -scheme MacShout -configuration Release build

# Or open in Xcode
open MacShout.xcodeproj
```

### Clean Build

```bash
# Remove derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/MacShout-*

# Remove XCFramework and regenerate
rm -rf Frameworks/whisper.xcframework
./scripts/setup.sh
```

## How It Works

1. **Hotkey Pressed**: CGEventTap captures the global key event
2. **Recording Starts**: AVAudioEngine captures microphone input
3. **Audio Processing**: Convert to 16kHz mono Float32 PCM (whisper.cpp format)
4. **Hotkey Released**: Stop recording and pass audio to whisper.cpp
5. **Transcription**: whisper.cpp runs on GPU via Metal
6. **Text Insertion**: Simulated paste (saves clipboard, copies text, sends Cmd+V, restores clipboard)

## Tech Stack

- **Language**: Swift 5.9, SwiftUI
- **Speech Recognition**: [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (OpenAI Whisper in C++)
- **Audio**: AVFoundation (AVAudioEngine)
- **Hotkey**: Carbon (CGEventTap)
- **Text Insertion**: Core Graphics (CGEvent)
- **UI**: SwiftUI (MenuBarExtra)
- **Build**: xcodegen

## Privacy

MacShout is completely private:
- All audio processing happens locally on your Mac
- No data is sent to any servers
- No analytics or tracking
- Models are downloaded once and cached locally
- Audio is not saved (only kept in memory during transcription)

## License

MIT License - see LICENSE file for details

## Acknowledgments

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) by Georgi Gerganov
- [Whisper](https://github.com/openai/whisper) by OpenAI
- Inspired by the need for local, private speech-to-text on macOS

## Support

If you encounter issues:
1. Check the Troubleshooting section above
2. Review the whisper.cpp documentation
3. Open an issue on GitHub (if this becomes public)

---

**Note**: First run may be slower as the Core ML encoder is compiled for your specific device. Subsequent runs will be much faster.
