#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/Protocol.swift Sources/Design.swift iOS/iLedBikeMobile/HalloweenDesigns.swift Tests/Checks.swift -framework AppKit -o .build/checks
.build/checks
