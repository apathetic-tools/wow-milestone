#!/bin/bash

set -euo pipefail

# Load local configuration
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.local.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found at $CONFIG_FILE" >&2
    echo "Please copy dev/config.sh.example to dev/config.local.sh and update it with your local paths" >&2
    exit 1
fi
source "$CONFIG_FILE"

ADDON_SUBPATH="/_retail_/Interface/AddOns"
WOW_ADDONS_DIR="${WOW_DIR%/}${ADDON_SUBPATH}"
ADDON_NAME="Milestone"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/$ADDON_NAME"

# Validate source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source addon directory not found at $SOURCE_DIR" >&2
    exit 1
fi

# Validate target directory exists
if [[ ! -d "$WOW_ADDONS_DIR" ]]; then
    echo "Error: WoW AddOns directory not found at $WOW_ADDONS_DIR" >&2
    exit 1
fi

TARGET_DIR="$WOW_ADDONS_DIR/$ADDON_NAME"

echo "Installing $ADDON_NAME addon..."
echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"

# Remove existing addon directory if it exists
if [[ -d "$TARGET_DIR" ]]; then
    echo "Removing existing $ADDON_NAME directory..."
    rm -rf "$TARGET_DIR"
fi

# Copy addon to WoW AddOns directory
cp -r "$SOURCE_DIR" "$TARGET_DIR"

echo "✓ $ADDON_NAME addon installed successfully!"
