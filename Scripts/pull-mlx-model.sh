#!/usr/bin/env bash
# pull-mlx-model.sh
#
# Download an MLX-community model from Hugging Face.
#
# Usage:
#   ./Scripts/pull-mlx-model.sh <hf-repo-id> [local-dir]
#   ./Scripts/pull-mlx-model.sh mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit
#
# Default local-dir: ~/.cache/huggingface/hub/<repo-id>
#
# Tool detection (first match wins):
#   1. hf             — alias / wrapper for huggingface-cli
#   2. uvx hf         — uv tool runner (if uv installed)
#   3. x uvx hf       — x-cmd wrapper (if x-cmd installed)
#
# Environment:
#   HF_ENDPOINT — mirror (default https://hf-mirror.com)
#   HF_TOKEN    — HF token for gated repos
#
# Examples:
#   ./Scripts/pull-mlx-model.sh mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit
#
set -euo pipefail

REPO="${1:?usage: $0 <hf-repo-id> [local-dir]}"
LOCAL_DIR="${2:-$HOME/.cache/huggingface/hub/$(echo "$REPO" | tr '/' '_')}"

export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

echo "==> Pulling $REPO"
echo "    → $LOCAL_DIR"
echo "    mirror: $HF_ENDPOINT"
echo

mkdir -p "$LOCAL_DIR"

if command -v hf >/dev/null 2>&1; then
    echo "Using: hf"
    hf download "$REPO" --local-dir "$LOCAL_DIR"
elif command -v uvx >/dev/null 2>&1; then
    echo "Using: uvx hf"
    uvx hf download "$REPO" --local-dir "$LOCAL_DIR"
elif command -v x >/dev/null 2>&1; then
    echo "Using: x uvx hf"
    x uvx hf download "$REPO" --local-dir "$LOCAL_DIR"
else
    echo "error: no hf / uvx / x-cmd found" >&2
    echo "       install one of:" >&2
    echo "         brew install uv" >&2
    echo "         # or: x install uv" >&2
    exit 1
fi

echo
echo "==> Done."
echo "    Model: $LOCAL_DIR"
echo "    Run:   macsay --engine mlx --mlx-model \"$LOCAL_DIR\" 'text'"