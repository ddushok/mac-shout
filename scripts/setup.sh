#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

WHISPER_VERSION="v1.8.3"
FRAMEWORK_URL="https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_VERSION}/whisper-${WHISPER_VERSION}-xcframework.zip"
FRAMEWORKS_DIR="${PROJECT_ROOT}/Frameworks"
ZIP_FILE="${FRAMEWORKS_DIR}/whisper.xcframework.zip"

echo "🔧 Setting up MacShout project..."

# Create directories
mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${PROJECT_ROOT}/MacShout/Whisper"
mkdir -p "${PROJECT_ROOT}/MacShout/Audio"
mkdir -p "${PROJECT_ROOT}/MacShout/Input"
mkdir -p "${PROJECT_ROOT}/MacShout/Views"

# Download whisper.cpp XCFramework
if [ ! -d "${FRAMEWORKS_DIR}/whisper.xcframework" ]; then
    echo "📦 Downloading whisper.cpp XCFramework ${WHISPER_VERSION}..."
    curl -L -o "${ZIP_FILE}" "${FRAMEWORK_URL}"
    
    echo "📂 Extracting XCFramework..."
    unzip -q "${ZIP_FILE}" -d "${FRAMEWORKS_DIR}"
    rm "${ZIP_FILE}"
    
    echo "✅ whisper.cpp XCFramework installed"
else
    echo "✅ whisper.cpp XCFramework already exists"
fi

# Create models directory in Application Support
MODELS_DIR="${HOME}/Library/Application Support/MacShout/Models"
mkdir -p "${MODELS_DIR}"
echo "✅ Models directory created at ${MODELS_DIR}"

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo "⚠️  xcodegen not found. Install it with: brew install xcodegen"
    exit 1
fi

echo "🎯 Generating Xcode project..."
cd "${PROJECT_ROOT}"
xcodegen generate

echo ""
echo "✨ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open MacShout.xcodeproj in Xcode"
echo "  2. Select your development team in project settings"
echo "  3. Build and run the project"
echo ""
echo "Note: The app requires Accessibility permissions to work."
echo "      Go to System Settings > Privacy & Security > Accessibility"
echo "      and enable MacShout when prompted."
