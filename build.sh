#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
quietglass_bin_dir="$(swift build -c release --show-bin-path)"
quietglass_universal="${QUIETGLASS_UNIVERSAL:-0}"
if [[ "$quietglass_universal" != 0 && "$quietglass_universal" != 1 ]]; then
    printf '%s\n' 'QUIETGLASS_UNIVERSAL must be 0 or 1.' >&2
    exit 1
fi
if [[ $# -gt 0 ]]; then
    quietglass_app="$1"
    quietglass_archive="${quietglass_app%.app}.zip"
else
    quietglass_app="../Build.noindex/QuietGlass.app"
    quietglass_archive="../QuietGlass.zip"
fi
if [[ "$quietglass_app" != *.app ]]; then
    printf '%s\n' 'The build output must be an .app bundle path.' >&2
    exit 1
fi
quietglass_signing_identity="${QUIETGLASS_SIGN_IDENTITY:-}"
if [[ -z "$quietglass_signing_identity" ]]; then
    quietglass_signing_identity="$(security find-identity -v -p codesigning | /usr/bin/awk '/"QuietGlass Local Development"/ { print $2; exit }')"
    if [[ -z "$quietglass_signing_identity" ]] && security find-certificate -c "QuietGlass Local Development" >/dev/null 2>&1; then
        printf '%s\n' 'The QuietGlass signing certificate exists, but its identity is unavailable. Repair it in Keychain Access; refusing to change the app identity.' >&2
        exit 1
    fi
    if [[ -z "$quietglass_signing_identity" ]]; then
        quietglass_signing_identity="$(security find-identity -v -p codesigning | /usr/bin/awk '/"Apple Development:/ { print $2; exit }')"
    fi
    quietglass_signing_identity="${quietglass_signing_identity:--}"
fi
quietglass_stage="$(mktemp -d "${TMPDIR:-/tmp}/quietglass-build.XXXXXX")"
trap 'rm -rf "$quietglass_stage"' EXIT
quietglass_staged_app="$quietglass_stage/QuietGlass.app"
mkdir -p "$quietglass_staged_app/Contents/MacOS" "$quietglass_staged_app/Contents/Resources"
cp "$quietglass_bin_dir/QuietGlass" "$quietglass_staged_app/Contents/MacOS/QuietGlass"
if [[ "$quietglass_universal" == 1 ]]; then
    for quietglass_arch in arm64 x86_64; do
        swift build -c release --triple "$quietglass_arch-apple-macosx14.0"
    done
    quietglass_arm_bin="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/QuietGlass"
    quietglass_intel_bin="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/QuietGlass"
    lipo -create "$quietglass_arm_bin" "$quietglass_intel_bin" -output "$quietglass_staged_app/Contents/MacOS/QuietGlass"
    lipo "$quietglass_staged_app/Contents/MacOS/QuietGlass" -verify_arch arm64 x86_64
fi
cp Resources/Info.plist "$quietglass_staged_app/Contents/Info.plist"
cp LICENSE "$quietglass_staged_app/Contents/Resources/LICENSE.txt"
cp Resources/Icons/LICENSE.md "$quietglass_staged_app/Contents/Resources/ThirdPartyNotices.txt"
cat Resources/Models/SFace-LICENSE.txt >> "$quietglass_staged_app/Contents/Resources/ThirdPartyNotices.txt"
cat Resources/Sounds/NOTICE.txt >> "$quietglass_staged_app/Contents/Resources/ThirdPartyNotices.txt"
xcrun coremlcompiler compile Sources/QuietGlass/Resources/SFace.mlmodel "$quietglass_staged_app/Contents/Resources"
cp Resources/Preview/BlurPreview.png "$quietglass_staged_app/Contents/Resources/BlurPreview.png"
cp Resources/Help.html "$quietglass_staged_app/Contents/Resources/QuietGlass Help.html"
cp Sources/QuietGlass/Resources/NearbyAlert.mp3 "$quietglass_staged_app/Contents/Resources/NearbyAlert.mp3"
xcrun actool Resources/AppIcon/QuietGlass.icon \
    --compile "$quietglass_staged_app/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon QuietGlass \
    --output-partial-info-plist "$quietglass_stage/icon-info.plist" \
    --output-format human-readable-text --warnings --errors
/usr/libexec/PlistBuddy -c "Merge $quietglass_stage/icon-info.plist" "$quietglass_staged_app/Contents/Info.plist"
codesign --force --sign "$quietglass_signing_identity" --identifier local.clinton.QuietGlass "$quietglass_staged_app"
quietglass_team="$(codesign -dv "$quietglass_staged_app" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/ { print $2 }')"
if [[ -n "$quietglass_team" && "$quietglass_team" != "not set" ]]; then
    python3 scripts/build-intents.py "$quietglass_bin_dir" "$quietglass_staged_app/Contents/Resources"
    codesign --force --sign "$quietglass_signing_identity" --identifier local.clinton.QuietGlass "$quietglass_staged_app"
else
    printf '%s\n' 'Shortcuts actions omitted: execution requires an Apple-signed developer identity with a Team ID.'
fi
if codesign -dv "$quietglass_staged_app" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:'; then
    codesign --force --sign "$quietglass_signing_identity" --identifier local.clinton.QuietGlass \
        --options runtime --timestamp --entitlements Resources/QuietGlass.entitlements "$quietglass_staged_app"
fi
codesign --verify --strict --all-architectures "$quietglass_staged_app"
mkdir -p "$(dirname "$quietglass_app")"
if [[ -d "$quietglass_app" ]]; then rm -rf "$quietglass_app"; fi
ditto --norsrc --noextattr "$quietglass_staged_app" "$quietglass_app"
ditto -c -k --keepParent --norsrc --noextattr "$quietglass_staged_app" "$quietglass_archive"
printf 'Built %s and %s\n' "$quietglass_app" "$quietglass_archive"
if [[ "$quietglass_signing_identity" == "-" ]]; then
    printf '%s\n' 'Ad-hoc build: changed binaries can require Screen Recording to be reapproved, then an app restart.'
    printf '%s\n' 'Set QUIETGLASS_SIGN_IDENTITY to an installed Apple Development identity to retain access across builds.'
fi
