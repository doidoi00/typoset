# MultiOCR

A powerful macOS menubar OCR application supporting multiple AI-powered OCR engines.

## Features

- 🎯 **Multiple OCR Engines**
  - Apple Vision Framework (Local, no API key required)
  - Gemini Vision AI
  - ChatGPT Vision (GPT-4o)
  - Mistral OCR (Pixtral)

- 🖱️ **Easy Screen Capture**
  - Crosshair selection tool
  - Visual feedback with dimensions
  - ESC to cancel

- ⌨️ **Global Keyboard Shortcuts**
  - `Cmd+Shift+1`: Capture with default engine
  - `Cmd+Shift+2`: Show quick capture menu

- 🔒 **Secure API Key Storage**
  - API keys stored in macOS Keychain
  - Never stored in plain text

- 📋 **Clipboard Integration**
  - Auto-copy OCR results to clipboard
  - Recent results history

## Requirements

- macOS 12.0 or later
- Xcode 14.0 or later (for building)
- API keys for AI engines (optional, Vision works without API key)

## Installation

### Option 1: Build from Source

1. Clone or download this repository
2. Open `MultiOCR.xcodeproj` in Xcode
3. Build and run (Cmd+R)

### Option 2: Open with Xcode from Terminal

```bash
cd /Users/jang-minyeop/Project/OCR
xed MultiOCR.xcodeproj
```

## Setup

1. **Grant Screen Recording Permission**
   - On first launch, macOS will prompt for screen recording permission
   - Go to System Preferences > Security & Privacy > Screen Recording
   - Enable MultiOCR

2. **Configure API Keys** (Optional)
   - Click the MultiOCR icon in the menubar
   - Select "Settings..."
   - Go to "API Keys" tab
   - Enter your API keys:
     - [Gemini API Key](https://makersuite.google.com/app/apikey)
     - [OpenAI API Key](https://platform.openai.com/api-keys)
     - [Mistral API Key](https://console.mistral.ai/api-keys/)

3. **Choose Default Engine**
   - In Settings > General
   - Select your preferred default OCR engine
   - Apple Vision works without any API key

## Usage

### Method 1: Keyboard Shortcuts
- Press `Cmd+Shift+1` to start capture with default engine
- Press `Cmd+Shift+2` to show quick capture menu

### Method 2: Menubar
- Click the MultiOCR icon in the menubar
- Select "Capture Screen Area" or choose an engine from "Quick Capture"

### Capturing
1. Crosshair cursor will appear
2. Click and drag to select the area
3. Release to capture
4. OCR text will be automatically copied to clipboard
5. Notification will confirm completion

## Project Structure

```
MultiOCR/
├── MultiOCR/
│   ├── MultiOCRApp.swift          # Main app entry point
│   ├── AppDelegate.swift          # App lifecycle & hotkeys
│   ├── Controllers/
│   │   └── StatusBarController.swift
│   ├── Managers/
│   │   ├── ScreenCaptureManager.swift
│   │   ├── OCRManager.swift
│   │   └── SettingsManager.swift
│   ├── Models/
│   │   ├── OCREngine.swift
│   │   └── OCRResult.swift
│   ├── OCREngines/
│   │   ├── VisionOCREngine.swift
│   │   ├── GeminiOCREngine.swift
│   │   ├── ChatGPTOCREngine.swift
│   │   └── MistralOCREngine.swift
│   ├── Views/
│   │   ├── SelectionOverlayWindow.swift
│   │   └── SettingsView.swift
│   ├── Utilities/
│   │   ├── KeychainHelper.swift
│   │   └── HotkeyManager.swift
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── MultiOCR.entitlements
└── MultiOCR.xcodeproj
```

## OCR Engines Comparison

| Engine | Speed | Accuracy | Cost | API Key Required |
|--------|-------|----------|------|------------------|
| Apple Vision | ⚡️⚡️⚡️ Fast | ⭐️⭐️⭐️ Good | Free | ❌ No |
| Gemini | ⚡️⚡️ Medium | ⭐️⭐️⭐️⭐️ Excellent | $ Low | ✅ Yes |
| ChatGPT | ⚡️ Slower | ⭐️⭐️⭐️⭐️⭐️ Best | $$ Medium | ✅ Yes |
| Mistral | ⚡️⚡️ Medium | ⭐️⭐️⭐️⭐️ Excellent | $ Low | ✅ Yes |

## Troubleshooting

### Screen capture not working
- Ensure Screen Recording permission is granted in System Preferences
- Restart the app after granting permission

### API errors
- Verify API keys are correct in Settings
- Check your API quota/credits
- Ensure you have internet connection for AI engines

### Keyboard shortcuts not working
- Check if another app is using the same shortcuts
- Try quitting and restarting MultiOCR

## Privacy

- All OCR processing with Apple Vision happens locally on your device
- API-based engines send images to their respective services
- API keys are stored securely in macOS Keychain
- No data is collected or stored by this application

## License

Copyright © 2024. All rights reserved.

## Credits

Inspired by [OwlOCR](https://owlocr.com)
