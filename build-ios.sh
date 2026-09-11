#!/bin/bash
# Build Camellia Player for iOS using macOS-hosted CI
# This script helps you trigger an iOS build via GitHub Actions

set -e

echo "========================================="
echo "Camellia Player iOS Build Helper"
echo "========================================="
echo ""

# Check if we're on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "[INFO] macOS detected. Building iOS locally..."
    flutter build ios --release
    echo "[SUCCESS] iOS build complete: build/ios/iphoneos/Runner.app"
else
    echo "[INFO] Non-macOS system detected: $OSTYPE"
    echo ""
    echo "iOS apps cannot be built directly on $OSTYPE."
    echo "Please use one of these options:"
    echo ""
    echo "Option 1: GitHub Actions (Free, recommended)"
    echo "  1. Push your code to GitHub"
    echo "  2. The workflow in .github/workflows/build-ios.yml will run automatically"
    echo "  3. Download the .app artifact from the Actions tab"
    echo ""
    echo "Option 2: Cloud Mac Services"
    echo "  - MacInCloud (https://www.macincloud.com)"
    echo "  - Codemagic (https://codemagic.io)"
    echo "  - GitHub Codespaces with macOS runner"
    echo ""
    echo "Option 3: Use a Mac"
    echo "  - Clone this repo on macOS"
    echo "  - Run: flutter pub get"
    echo "  - Run: flutter build ios --release"
fi
