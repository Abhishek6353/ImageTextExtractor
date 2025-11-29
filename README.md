# TextSnap

A simple iOS app that extracts text from images using Apple's Vision framework with a Photos-like interface.

## Features

- 📸 Select images from photo library
- 🔍 Automatic text detection using Vision framework
- 👆 Tap any text area to copy instantly
- 📋 Copy all detected text at once
- 🎨 Clean iOS-style overlay interface
- 
## Screenshots

<p float="left">
  <img src="Screenshots/Screen_1.png" width="220" />
  <img src="Screenshots/Screen_2.png" width="220" />
</p>

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

```bash
git clone https://github.com/Abhishek6353/ImageTextExtractor.git
cd ImageTextExtractor
open ImageTextExtractor.xcodeproj
```

## How to Use

1. Tap **Select Image** to choose a photo
2. Tap **Scan** to detect text
3. Tap any highlighted text area to copy
4. Tap **Copy All** to copy everything
5. Tap the blue button to exit scan mode

## Technologies

- SwiftUI
- Vision Framework
- PhotosUI
- Canvas with blend modes

## License

MIT License - feel free to use this project however you'd like!

## Contributing

Pull requests are welcome! Feel free to improve the text grouping algorithm or add new features.

---

⭐ Star this repo if you find it useful!
