#!/usr/bin/env bash
# Build the Play Store release bundle with code obfuscation enabled and
# debug symbols split out (needed to de-obfuscate a crash stack trace later,
# but never uploaded to the Play Store itself — keep this folder safe).
#
# Requires android/key.properties to already exist (see
# android/key.properties.example) — otherwise this still builds, but signed
# with the debug key, which the Play Store will reject on upload.
set -euo pipefail
cd "$(dirname "$0")/../.."

SYMBOLS_DIR="build/symbols/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SYMBOLS_DIR"

flutter build appbundle --release \
  --obfuscate \
  --split-debug-info="$SYMBOLS_DIR"

echo ""
echo "Built: build/app/outputs/bundle/release/app-release.aab"
echo "Debug symbols (keep private, do not upload): $SYMBOLS_DIR"
