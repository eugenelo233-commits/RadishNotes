#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
xcrun swiftc -swift-version 5 -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx14.0 -module-cache-path .build/ModuleCache Sources/Model.swift Sources/Preferences.swift Sources/PhysicsModel.swift Sources/FocusModel.swift Tests/main.swift -o .build/ModelTests -framework AppKit
.build/ModelTests
