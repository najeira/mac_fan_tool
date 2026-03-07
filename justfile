set dotenv-load := true
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

app_name := "MacFanTool"
app_file := "build/macos/Build/Products/Release/" + app_name + ".app"
notary_zip_file := app_name + "-notary.zip"
release_zip_file := app_name + ".zip"
frameworks_dir := app_file + "/Contents/Frameworks"
helper_file := app_file + "/Contents/Library/LaunchServices/FanControlHelper"
launch_daemon_plist := app_file + "/Contents/Library/LaunchDaemons/FanControlHelper.plist"
installed_app_file := "/Applications/" + app_name + ".app"
installed_helper_file := installed_app_file + "/Contents/Library/LaunchServices/FanControlHelper"

default:
  just --list

build-release:
  flutter build macos --release

test:
  flutter test

format:
  dart format .

analyze:
  flutter analyze

icon:
  dart run flutter_launcher_icons

check-signing-env:
  test -n "${APPLE_SIGN_NAME:-}"
  test -n "${APPLE_TEAM_ID:-}"
  security find-identity -v -p codesigning
  security find-identity -v -p codesigning | grep -F "${APPLE_SIGN_NAME}" > /dev/null

check-notary-env:
  test -n "${APPLE_EMAIL_ADDRESS:-}"
  test -n "${APPLE_TEAM_ID:-}"
  test -n "${APP_SPECIFIC_PASSWORD:-}"

show-signing-targets:
  printf 'App: %s\n' "{{app_file}}"
  printf 'Helper: %s\n' "{{helper_file}}"
  printf 'LaunchDaemon: %s\n' "{{launch_daemon_plist}}"
  printf 'Installed app: %s\n' "{{installed_app_file}}"
  printf 'Notary ZIP: %s\n' "{{notary_zip_file}}"
  printf 'Release ZIP: %s\n' "{{release_zip_file}}"

sign-frameworks: build-release check-signing-env
  shopt -s nullglob; for item in "{{frameworks_dir}}"/*.framework "{{frameworks_dir}}"/*.dylib; do echo "Signing nested code: $item"; codesign --force --timestamp --sign "${APPLE_SIGN_NAME}" "$item"; done

sign-helper: build-release check-signing-env
  test -f "{{helper_file}}"
  echo "Signing helper: {{helper_file}}"
  codesign --force --timestamp --options runtime --sign "${APPLE_SIGN_NAME}" "{{helper_file}}"

sign-app: sign-frameworks sign-helper
  test -f "{{launch_daemon_plist}}"
  echo "Signing app bundle: {{app_file}}"
  codesign --force --timestamp --options runtime --entitlements=macos/Runner/Release.entitlements --sign "${APPLE_SIGN_NAME}" "{{app_file}}"

sign-release: sign-app

verify-release:
  codesign --verify --deep --strict --verbose=4 {{app_file}}
  spctl --assess --verbose {{app_file}}
  codesign -dv --verbose=4 {{app_file}}
  codesign -dv --verbose=4 {{helper_file}}
  codesign -d --entitlements - {{app_file}}
  codesign -d --entitlements - {{helper_file}}

zip-notary: sign-release verify-release
  rm -f "{{notary_zip_file}}"
  ditto -c -k --sequesterRsrc --keepParent "{{app_file}}" "{{notary_zip_file}}"

notary-submit: zip-notary check-notary-env
  xcrun notarytool submit "{{notary_zip_file}}" --apple-id "${APPLE_EMAIL_ADDRESS}" --team-id "${APPLE_TEAM_ID}" --password "${APP_SPECIFIC_PASSWORD}" --wait

notary-log submission_id:
  xcrun notarytool log "{{submission_id}}" --apple-id "${APPLE_EMAIL_ADDRESS}" --team-id "${APPLE_TEAM_ID}" --password "${APP_SPECIFIC_PASSWORD}"

staple-release: notary-submit
  xcrun stapler staple {{app_file}}

verify-stapled: staple-release
  xcrun stapler validate {{app_file}}
  spctl --assess --verbose {{app_file}}

zip-release: verify-stapled
  rm -f "{{release_zip_file}}"
  ditto -c -k --sequesterRsrc --keepParent "{{app_file}}" "{{release_zip_file}}"

install-release:
  ditto "{{app_file}}" "{{installed_app_file}}"

verify-installed:
  codesign --verify --deep --strict --verbose=4 "{{installed_app_file}}"
  codesign --verify --strict --verbose=4 "{{installed_helper_file}}"
  plutil -p "{{installed_app_file}}/Contents/Library/LaunchDaemons/FanControlHelper.plist"

dist: zip-release
