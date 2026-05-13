#!/usr/bin/env bash
# Launch nested kwin_wayland with mismatched virtual outputs to exercise
# CursorEdgeTeleport without needing physical hardware.
#
# Layout produced (single row, scaled-down BEAST analogue):
#   [1920x1080 4K-stand-in] [1280x720 2K-stand-in, offset+180] [1920x1080]
#
# If the middle output isn't vertically centered, kscreen-doctor inside
# the nested session can adjust it:
#   kscreen-doctor output.1.position.1920,180
#
# Usage:
#   ./nested-test.sh                          # use installed kwin_wayland
#   ./nested-test.sh /path/to/kwin_wayland    # use a specific binary
set -euo pipefail

KWIN_BIN="${1:-kwin_wayland}"

export QT_LOGGING_RULES="kwin_core.debug=true;${QT_LOGGING_RULES:-}"

echo "Launching nested $KWIN_BIN with 3 virtual outputs..."
echo "Set [CursorEdgeTeleport]/Enabled=true in kwinrc to activate teleport."
echo "Watch for 'CursorEdgeTeleport: warped from ...' log lines below."
echo "---"

"$KWIN_BIN" --xwayland \
    --width 1920 --height 1080 \
    --width 1280 --height 720 \
    --width 1920 --height 1080 \
    --output-count 3
