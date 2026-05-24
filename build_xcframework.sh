#!/bin/bash

# MDEditorKit XCFramework Build Script
# Bundles MDEditorKit as a binary XCFramework usable from any Xcode project
# without requiring SwiftPM.

set -euo pipefail

FRAMEWORK_NAME="MDEditorKit"
OUTPUT_DIR="./build"
XCFRAMEWORK_PATH="${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"
ZIP_PATH="${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework.zip"

# 1. Generate Xcode Project
echo "==> Generating Xcode project using xcodegen..."
if ! command -v xcodegen &> /dev/null; then
    echo "xcodegen not found, install with: brew install xcodegen"
    exit 1
fi
xcodegen generate

# 2. Clean previous builds
echo "==> Cleaning old build artifacts..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# 3. Archive for macOS (Apple Silicon + Intel — generic destination produces a fat binary)
echo "==> Archiving for macOS..."
xcodebuild archive \
    -project "${FRAMEWORK_NAME}.xcodeproj" \
    -scheme "${FRAMEWORK_NAME}" \
    -destination "generic/platform=macOS" \
    -archivePath "${OUTPUT_DIR}/macOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    | xcbeautify || true

# 4. Create XCFramework
echo "==> Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework "${OUTPUT_DIR}/macOS.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
    -output "${XCFRAMEWORK_PATH}"

# 5. Zip it for distribution
echo "==> Zipping XCFramework for distribution..."
(
    cd "${OUTPUT_DIR}"
    rm -f "${FRAMEWORK_NAME}.xcframework.zip"
    # -y preserves symlinks so the framework's `Versions/Current` keeps working after unzip
    zip -qry "${FRAMEWORK_NAME}.xcframework.zip" "${FRAMEWORK_NAME}.xcframework"
)

# 6. Emit checksum (handy for SwiftPM binaryTarget consumers down the road)
if command -v swift &> /dev/null; then
    CHECKSUM=$(swift package compute-checksum "${ZIP_PATH}" 2>/dev/null || true)
    if [ -n "${CHECKSUM}" ]; then
        echo "${CHECKSUM}" > "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework.zip.checksum"
        echo "==> Checksum: ${CHECKSUM}"
    fi
fi

echo "==> Done. XCFramework at: ${XCFRAMEWORK_PATH}"
echo "==> Distribution zip at: ${ZIP_PATH}"
