#!/usr/bin/env bash
# Build gate: iOS app on the iPhone Duo simulator, plus the tvOS target (shared sources).
export ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PROJECT_TYPE=xcodeproj
export PROJECT="Moonlight.xcodeproj"
export SCHEME="Moonlight"
export CONFIGURATION="Debug"
export SIM_NAME="iPhone Duo"
export RUN_TESTS=0
export RUN_LINT=0

if [[ "$1" != "--fast" ]]; then
    if ! xcodebuild -project Moonlight.xcodeproj -scheme "Moonlight TV" -configuration Debug -sdk appletvsimulator build -quiet; then
        echo "❌ verify FAIL: tvOS target does not build"
        exit 1
    fi
fi

exec ~/.claude/templates/verify-core.sh "$@"
