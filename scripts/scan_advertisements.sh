#!/bin/bash
# Read-only BLE discovery; redirect output into .build/ to keep nearby identities private.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache
cat > .build/scan-info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.iledbike.advertisement-scanner</string>
<key>CFBundleName</key><string>iLedBike Read-only Bluetooth Scanner</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Look for the bike remote's Bluetooth advertisements without connecting or changing devices.</string>
</dict></plist>
PLIST
xcrun swiftc -module-cache-path .build/ModuleCache scripts/scan_advertisements.swift -framework CoreBluetooth \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker .build/scan-info.plist \
  -o .build/scan-advertisements
exec .build/scan-advertisements "${1:-25}"
