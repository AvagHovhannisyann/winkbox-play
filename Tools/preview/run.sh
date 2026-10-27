#!/bin/bash
# Builds and runs the Mac preview of the app's own screens: Tools/preview/run.sh <outdir>
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build "${1:-.build/preview-out}"
swiftc -DWB_NO_KEYCHAIN -module-cache-path .build/ModuleCache App/Core/PlayLink.swift App/Core/WBCrypto.swift App/UI/ConnectView.swift \
  Tools/preview/main.swift -o .build/preview
.build/preview "${1:-.build/preview-out}"
