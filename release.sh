#!/usr/bin/env bash
#
# Cut a new GitHub release: bump CFBundleShortVersionString in Info.plist,
# commit + push, build, package zip, create the release with the zip
# attached. Usage:
#
#     ./release.sh 0.2 "FluidAudio bump, faster Parakeet"
#
# Requires `gh` to be installed and authenticated.
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <version> [notes]"
    echo "Example: $0 0.2 'FluidAudio bump'"
    exit 1
fi

VERSION="$1"
NOTES="${2:-Release v$VERSION}"
TAG="v${VERSION}"
PLIST="Resources/Info.plist"
APP="VoicePTT.app"
ZIP="VoicePTT-${VERSION}.zip"

# Refuse to release on top of uncommitted work — the version bump should be
# the only change in this release commit.
if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Working tree is dirty. Commit or stash first."
    exit 1
fi

# Refuse if tag already exists locally or remotely.
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "✗ Tag $TAG already exists locally."
    exit 1
fi
if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
    echo "✗ Tag $TAG already exists on origin."
    exit 1
fi

echo "==> Bumping CFBundleShortVersionString to $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"

echo "==> Committing and pushing version bump"
git add "$PLIST"
git commit -m "release: $TAG"
git push

echo "==> Building"
# Use build.sh directly (not build-and-run.sh) — keeping the old version
# live lets us test the in-app 'Download & install' flow against the
# new release we're about to publish.
./build.sh >/dev/null

echo "==> Packaging $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Creating GitHub release"
gh release create "$TAG" "$ZIP" --title "$TAG" --notes "$NOTES"

echo
echo "✓ Done: https://github.com/dmakhmutov/voice-ptt/releases/tag/$TAG"
