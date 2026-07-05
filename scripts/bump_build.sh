#!/usr/bin/env bash
# bump_build.sh — increment the build number in project.yml and project.pbxproj,
# then commit so the repo stays in sync with App Store Connect.
#
# Usage:
#   ./scripts/bump_build.sh            # auto-increment
#   ./scripts/bump_build.sh 63         # set a specific number (e.g. to catch up to ASC)
#
# To wire into Xcode so it runs automatically on every Archive:
#   1. Product → Scheme → Edit Scheme → Archive → Pre-actions
#   2. Add a "Run Script" action, set shell to /bin/bash, paste:
#        "${SRCROOT}/scripts/bump_build.sh"
#   3. Set "Provide build settings from" to HaleHubIOS

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$REPO_ROOT/project.yml"
PBXPROJ="$REPO_ROOT/HaleHubIOS.xcodeproj/project.pbxproj"

# Read current build number from project.yml
CURRENT=$(grep 'CURRENT_PROJECT_VERSION' "$PROJECT_YML" | sed 's/.*"\([0-9]*\)".*/\1/')

if [[ -z "$CURRENT" ]]; then
    echo "error: could not read CURRENT_PROJECT_VERSION from project.yml" >&2
    exit 1
fi

# Use provided number or auto-increment
if [[ $# -ge 1 && "$1" =~ ^[0-9]+$ ]]; then
    NEXT="$1"
else
    NEXT=$((CURRENT + 1))
fi

echo "Build number: $CURRENT → $NEXT"

# Update project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: \"${CURRENT}\"/CURRENT_PROJECT_VERSION: \"${NEXT}\"/" "$PROJECT_YML"

# Update project.pbxproj — all 4 occurrences (Debug + Release × main + ShareExtension)
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT};/CURRENT_PROJECT_VERSION = ${NEXT};/g" "$PBXPROJ"

# Verify the replacements landed
UPDATED=$(grep -c "CURRENT_PROJECT_VERSION = ${NEXT};" "$PBXPROJ")
echo "Updated $UPDATED occurrences in project.pbxproj"

# Commit
cd "$REPO_ROOT"
git add "$PROJECT_YML" "$PBXPROJ"
git commit -m "chore(build): bump build number to ${NEXT}"

echo ""
echo "Done — build ${NEXT} committed. Run 'git push' to sync."
