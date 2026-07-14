#!/usr/bin/env bash
# verify_project.sh — regenerate the Xcode project from project.yml and assert
# the pieces that have silently vanished on regen before are still present:
# the Share Extension target + embed, both App Group entitlements, and the
# shared scheme. Run this before archiving for TestFlight, or in CI.
#
#   ./scripts/verify_project.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "→ xcodegen generate"
xcodegen generate >/dev/null

pbx="HaleHubIOS.xcodeproj/project.pbxproj"
scheme="HaleHubIOS.xcodeproj/xcshareddata/xcschemes/HaleHubIOS.xcscheme"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }

check "ShareExtension target present"            "grep -q ShareExtension '$pbx'"
check "ShareExtension.appex embed phase"         "grep -q '\.appex' '$pbx'"
check "App Group entitlement (app) wired"        "grep -q 'HaleHubIOS.entitlements' '$pbx'"
check "App Group entitlement (extension) wired"  "grep -q 'ShareExtension.entitlements' '$pbx'"
check "Shared scheme present"                    "test -f '$scheme'"

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "✗ project verification FAILED — something defined in project.yml is missing" >&2
  echo "  after regeneration. Do NOT archive. See docs/SHARE_EXTENSION.md." >&2
  exit 1
fi
echo "✓ project verification passed — safe to archive"
