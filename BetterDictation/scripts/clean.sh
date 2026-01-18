#!/bin/bash

# Clean Script for BetterDictation
# Removes app data (models, preferences, cache)
# Permissions are preserved (manual reset required in System Settings)

set -e

echo "Cleaning BetterDictation data..."

# Remove downloaded models
MODELS_DIR="$HOME/Library/Application Support/BetterDictation"
if [ -d "$MODELS_DIR" ]; then
    rm -rf "$MODELS_DIR"
    echo "  Removed models"
fi

# Remove app preferences
PREFS_FILE="$HOME/Library/Preferences/com.betterdictation.app.plist"
if [ -f "$PREFS_FILE" ]; then
    rm -f "$PREFS_FILE"
    echo "  Removed preferences"
fi

# Remove any caches
CACHE_DIR="$HOME/Library/Caches/com.betterdictation.app"
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "  Removed cache"
fi

echo ""
echo "Done. Run 'swift run' to start the app."
