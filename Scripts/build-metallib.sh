#!/usr/bin/env bash
# build-metallib.sh
#
# Compile mlx-swift's Metal shaders into mlx.metallib and place it next to the
# macsay binary. mlx-swift's SwiftPM build can't generate Metal kernels on its
# own (needs the Metal toolchain + Xcode), so we do it manually.
#
# Run from a build that has already resolved mlx-swift (so .build/checkouts/mlx-swift
# exists). The script is idempotent — re-run after any mlx-swift version bump.
#
# Requirements:
#   - Xcode with Metal toolchain (`xcrun metal` available)
#   - SwiftPM already resolved the macsay package (`swift package resolve`)
#
# Usage:
#   ./Scripts/build-metallib.sh                 # build then copy
#   DEVELOPER_DIR=/path/to/Xcode.app ./Scripts/build-metallib.sh
set -euo pipefail

cd "$(dirname "$0")/.."

CHECKOUT=".build/checkouts/mlx-swift"
METAL_SRC="$CHECKOUT/Source/Cmlx/mlx-generated/metal"
BUILD_DIR=".build/release"
PRIVATE_METAL_DIR="$BUILD_DIR/mlx_metallib"
OUTPUT="$BUILD_DIR/mlx.metallib"

if [ ! -d "$METAL_SRC" ]; then
    echo "error: $METAL_SRC not found" >&2
    echo "       run 'swift package resolve' first" >&2
    exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: xcrun not found — install Xcode" >&2
    exit 1
fi

mkdir -p "$PRIVATE_METAL_DIR"

echo "Compiling Metal kernels from $METAL_SRC ..."
for src in "$METAL_SRC"/*.metal; do
    name=$(basename "$src" .metal)
    xcrun metal -x metal -Wall -Wextra -fno-fast-math \
        -I"$METAL_SRC" \
        -c "$src" -o "$PRIVATE_METAL_DIR/$name.air"
done

# Steel attention kernels (subdirectory)
if [ -f "$METAL_SRC/steel/attn/kernels/steel_attention.metal" ]; then
    xcrun metal -x metal -Wall -Wextra -fno-fast-math \
        -I"$METAL_SRC" -I"$METAL_SRC" \
        -c "$METAL_SRC/steel/attn/kernels/steel_attention.metal" \
        -o "$PRIVATE_METAL_DIR/steel_attention.air"
fi

echo "Packaging mlx.metallib ..."
xcrun metallib -o "$OUTPUT" "$PRIVATE_METAL_DIR"/*.air

# Also place alongside the installed binary so end-users don't have to
# build it themselves. Update this path if you install elsewhere.
if [ -d "$HOME/.local/bin" ]; then
    cp "$OUTPUT" "$HOME/.local/bin/mlx.metallib"
    echo "Copied mlx.metallib to ~/.local/bin/"
fi

echo "Done: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"