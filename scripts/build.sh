#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache "dist/iLedBike Studio.app/Contents/MacOS" "dist/iLedBike Studio.app/Contents/Resources"
xcrun swiftc -swift-version 5 -O -module-cache-path .build/ModuleCache \
  Sources/Protocol.swift Sources/Design.swift Sources/PixelPreview.swift Sources/PixelDrawing.swift Sources/Bluetooth.swift Sources/App.swift \
  -framework AppKit -framework SwiftUI -framework CoreBluetooth -framework Combine \
  -o "dist/iLedBike Studio.app/Contents/MacOS/iLedBikeStudio"
cp Info.plist "dist/iLedBike Studio.app/Contents/Info.plist"
codesign --force --sign - "dist/iLedBike Studio.app"
plutil -lint "dist/iLedBike Studio.app/Contents/Info.plist"
