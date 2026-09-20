#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
quietglass_bin_dir="$(swift build -c release --show-bin-path)"
quietglass_app="${1:-../QuietGlass.app}"
quietglass_stage="$(mktemp -d "${TMPDIR:-/tmp}/quietglass-build.XXXXXX")"
trap 'rm -rf "$quietglass_stage"' EXIT
quietglass_staged_app="$quietglass_stage/QuietGlass.app"
mkdir -p "$quietglass_staged_app/Contents/MacOS" "$quietglass_staged_app/Contents/Resources"
cp "$quietglass_bin_dir/QuietGlass" "$quietglass_staged_app/Contents/MacOS/QuietGlass"
cp Resources/Info.plist "$quietglass_staged_app/Contents/Info.plist"
cp Resources/Hugeicons/LICENSE.md "$quietglass_staged_app/Contents/Resources/Hugeicons-LICENSE.md"
codesign --force --sign - --identifier local.clinton.QuietGlass "$quietglass_staged_app"
codesign --verify --strict "$quietglass_staged_app"
# Sign and archive outside Documents: sync providers can attach Finder metadata to
# an unpacked bundle there. The zip preserves a clean, verified distribution copy.
mkdir -p "$(dirname "$quietglass_app")"
ditto --norsrc --noextattr "$quietglass_staged_app" "$quietglass_app"
ditto -c -k --keepParent --norsrc --noextattr "$quietglass_staged_app" "${quietglass_app%.app}.zip"
printf 'Built %s and %s\n' "$quietglass_app" "${quietglass_app%.app}.zip"
