#!/bin/bash
# Usage: ./scripts/push.sh [commit-message]
# Bumps the Android build number in pubspec.yaml, commits, then pushes.

set -e

PUBSPEC="pubspec.yaml"
BRANCH="${2:-main}"

# ── Read current version ──────────────────────────────────────────────────────
CURRENT_LINE=$(grep "^version:" "$PUBSPEC")
VERSION_NAME=$(echo "$CURRENT_LINE" | sed 's/version: //' | cut -d'+' -f1)
BUILD_NUM=$(echo "$CURRENT_LINE" | cut -d'+' -f2)
NEW_BUILD=$((BUILD_NUM + 1))

# ── Bump pubspec.yaml ─────────────────────────────────────────────────────────
sed -i '' "s/^version:.*/version: ${VERSION_NAME}+${NEW_BUILD}/" "$PUBSPEC"
echo "✅  Version bumped: ${VERSION_NAME}+${BUILD_NUM} → ${VERSION_NAME}+${NEW_BUILD}"

# ── Commit version bump ───────────────────────────────────────────────────────
git add "$PUBSPEC"
git commit -m "chore: bump build number to ${NEW_BUILD}"

# ── Push ──────────────────────────────────────────────────────────────────────
git push origin "$BRANCH"
echo "🚀  Pushed to origin/${BRANCH}"
