#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "usage: $0 <semantic-version>"
  exit 64
fi

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  print -u2 "DEVELOPER_ID_APPLICATION must name a Developer ID Application certificate."
  exit 64
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  print -u2 "DEVELOPMENT_TEAM must contain the Apple Developer Team ID."
  exit 64
fi

if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
  print -u2 "NOTARYTOOL_PROFILE must name credentials stored in Keychain by notarytool."
  exit 64
fi

release_version="$1"
build_number="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
script_dir="${0:A:h}"
project_dir="${script_dir:h}"
archive_path="$project_dir/dist/Coast-$release_version.xcarchive"
output_dir="$project_dir/dist/$release_version"

if [[ -e "$archive_path" || -e "$output_dir" ]]; then
  print -u2 "Release output already exists for $release_version; choose a new version or move it aside."
  exit 73
fi

temporary_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT

mkdir -p "$output_dir"

xcodebuild \
  -project "$project_dir/Coast.xcodeproj" \
  -scheme Coast \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$archive_path" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$release_version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean archive

app_path="$archive_path/Products/Applications/Coast.app"
submission_zip="$temporary_dir/Coast-notarization.zip"
release_zip="$output_dir/Coast-$release_version-macOS.zip"
release_zip_name="${release_zip:t}"
submission_result="$temporary_dir/Coast-notarization-result.json"
notarization_log="$output_dir/Coast-$release_version-notarization-log.json"

codesign --verify --deep --strict --verbose=2 "$app_path"
lipo "$app_path/Contents/MacOS/Coast" -verify_arch arm64 x86_64

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_zip"
set +e
xcrun notarytool submit "$submission_zip" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait \
  --output-format json > "$submission_result"
notarytool_exit=$?
set -e

sed -n '1,200p' "$submission_result"
submission_id="$(plutil -extract id raw -o - "$submission_result")"
submission_status="$(plutil -extract status raw -o - "$submission_result")"
xcrun notarytool log \
  "$submission_id" \
  "$notarization_log" \
  --keychain-profile "$NOTARYTOOL_PROFILE"

if [[ $notarytool_exit -ne 0 || "$submission_status" != "Accepted" ]]; then
  print -u2 "Notarization was not accepted. Inspect $notarization_log."
  exit 65
fi

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_zip"
(
  cd "$output_dir"
  shasum -a 256 "$release_zip_name" | tee "$release_zip_name.sha256"
)
spctl --assess --type execute --verbose=2 "$app_path"

print "Release artifact: $release_zip"
print "Notarization log: $notarization_log"
