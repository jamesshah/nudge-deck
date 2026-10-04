#!/usr/bin/env bash
# Finish commit + push for the Xcode Cloud TestFlight setup branch.
# Agent shell was unavailable; run once from the repo root:
#   ./scripts/push-xcloud-setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

git checkout feat/xcloud-workflow-setup

cd ios/NudgeDeck
xcodegen generate
cd ../..

git add \
  .gitignore \
  ios/NudgeDeck/NudgeDeck.xcodeproj \
  ios/NudgeDeck/Support/Info.plist \
  ios/NudgeDeck/Config/App.xcconfig \
  ios/NudgeDeck/Config/Production.xcconfig \
  ios/NudgeDeck/project.yml \
  README.md \
  AGENTS.md \
  scripts/push-xcloud-setup.sh

if git diff --cached --name-only | grep -E 'Local\.xcconfig|(^|/)\.env(\.|$)'; then
  echo "ERROR: secret/local config staged — aborting" >&2
  exit 1
fi

git commit -m "$(cat <<'EOF'
Track Xcode project for Xcode Cloud TestFlight archives.

Commit generated project and Info.plist, set staging team/URL in App.xcconfig, and document Internal+External TestFlight workflow within the free hour budget.
EOF
)"

git push -u origin HEAD
git status -sb
echo "Commit: $(git rev-parse HEAD)"
echo "Remote: $(git remote get-url origin)"
