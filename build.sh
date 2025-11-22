#!/bin/bash

# MultiOCR Build Script
# This script builds the MultiOCR app from the command line

set -e

echo "🔨 Building MultiOCR..."
echo ""

# Check if Xcode is properly configured
if ! xcodebuild -version &> /dev/null; then
    echo "❌ Error: xcodebuild not found or not configured"
    echo "Please run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# Build the project
xcodebuild \
    -project MultiOCR.xcodeproj \
    -scheme MultiOCR \
    -configuration Debug \
    clean build

echo ""
echo "✅ Build completed successfully!"
echo "📦 App location: build/Debug/MultiOCR.app"
