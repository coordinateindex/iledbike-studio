#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -d "dist/iLedBike Studio.app" ]]; then bash scripts/build.sh; fi
open "dist/iLedBike Studio.app"
