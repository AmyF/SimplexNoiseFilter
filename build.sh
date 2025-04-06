#!/bin/bash
set -e

METAL_SOURCE="Sources/SimplexNoiseFilter/kernel/SimplexNoise.ci.metal"
HEADER_PATH="Sources/SimplexNoiseFilter/kernel/SimplexNoise.h"
AIR_OUTPUT="Sources/SimplexNoiseFilter/resources/SimplexNoise.ci.air"
METALIB_OUTPUT="Sources/SimplexNoiseFilter/resources/SimplexNoise.ci.metallib"

# 清理旧文件（强制覆盖）
rm -f "$AIR_OUTPUT" "$METALIB_OUTPUT" 2>/dev/null || true

echo "🛠  Compiling Metal kernel..."
xcrun metal -c \
    -I "$HEADER_PATH" \
    -fcikernel "$METAL_SOURCE" \
    -o "$AIR_OUTPUT"

echo "📦 Packaging Metallib..."
xcrun metallib -cikernel "$AIR_OUTPUT" \
    -o "$METALIB_OUTPUT"

echo "✅ Done! Metallib saved to: $METALIB_OUTPUT"