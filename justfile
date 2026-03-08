set dotenv-load := true
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

app_name := "MacFanTool"
xcode_workspace := "macos/Runner.xcworkspace"
xcode_scheme := "Runner"
macos_test_derived_data := "/tmp/mac_fan_tool-native-tests"
build_dir := "build/macos/Build/Products/Release"
dist_dir := "build/dist"
app_file := build_dir + "/" + app_name + ".app"
notary_zip_file := dist_dir + "/" + app_name + "-notary.zip"
release_zip_file := dist_dir + "/" + app_name + ".zip"
dmg_stage_dir := dist_dir + "/" + app_name + "-dmg"
temp_dmg_file := dist_dir + "/" + app_name + "-temp.dmg"
release_dmg_file := dist_dir + "/" + app_name + ".dmg"
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

test-macos:
  xcodebuild test -workspace "{{xcode_workspace}}" -scheme "{{xcode_scheme}}" -destination 'platform=macOS,arch=arm64' -derivedDataPath "{{macos_test_derived_data}}"

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
  printf 'Release DMG: %s\n' "{{release_dmg_file}}"

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

prepare-release: sign-release verify-release

verify-release:
  codesign --verify --deep --strict --verbose=4 {{app_file}}
  spctl --assess --verbose {{app_file}}
  codesign -dv --verbose=4 {{app_file}}
  codesign -dv --verbose=4 {{helper_file}}
  codesign -d --entitlements - {{app_file}}
  codesign -d --entitlements - {{helper_file}}

package-app-zip archive_path:
  mkdir -p "{{dist_dir}}"
  rm -f "{{archive_path}}"
  ditto -c -k --sequesterRsrc --keepParent "{{app_file}}" "{{archive_path}}"

zip-notary: prepare-release
  just package-app-zip "{{notary_zip_file}}"

notary-submit-file artifact: check-notary-env
  xcrun notarytool submit "{{artifact}}" --apple-id "${APPLE_EMAIL_ADDRESS}" --team-id "${APPLE_TEAM_ID}" --password "${APP_SPECIFIC_PASSWORD}" --wait

notary-submit: zip-notary
  just notary-submit-file "{{notary_zip_file}}"

notary-log submission_id:
  xcrun notarytool log "{{submission_id}}" --apple-id "${APPLE_EMAIL_ADDRESS}" --team-id "${APPLE_TEAM_ID}" --password "${APP_SPECIFIC_PASSWORD}"

staple-file artifact:
  xcrun stapler staple "{{artifact}}"

validate-stapled-file artifact:
  xcrun stapler validate "{{artifact}}"

sign-disk-image disk_image: check-signing-env
  codesign --force --timestamp --sign "${APPLE_SIGN_NAME}" "{{disk_image}}"

verify-disk-image disk_image:
  codesign --verify --verbose=4 "{{disk_image}}"
  spctl -a -t open --context context:primary-signature -v "{{disk_image}}"

staple-release: notary-submit
  just staple-file "{{app_file}}"

verify-stapled: staple-release
  just validate-stapled-file "{{app_file}}"
  spctl --assess --verbose {{app_file}}

zip-release: verify-stapled
  just package-app-zip "{{release_zip_file}}"

dmg-stage: prepare-release
  rm -rf "{{dmg_stage_dir}}"
  mkdir -p "{{dmg_stage_dir}}"
  ditto "{{app_file}}" "{{dmg_stage_dir}}/{{app_name}}.app"
  ln -s /Applications "{{dmg_stage_dir}}/Applications"

dmg-create: dmg-stage
  mkdir -p "{{dist_dir}}"
  rm -f "{{temp_dmg_file}}" "{{release_dmg_file}}"
  hdiutil create -volname "{{app_name}}" -srcfolder "{{dmg_stage_dir}}" -fs HFS+ -format UDRW -ov "{{temp_dmg_file}}"
  hdiutil convert "{{temp_dmg_file}}" -format UDZO -ov -o "{{dist_dir}}/{{app_name}}"

dmg-sign: dmg-create
  just sign-disk-image "{{release_dmg_file}}"

dmg-verify: dmg-sign
  just verify-disk-image "{{release_dmg_file}}"

dmg-notary-submit: dmg-verify
  just notary-submit-file "{{release_dmg_file}}"

dmg-staple: dmg-notary-submit
  just staple-file "{{release_dmg_file}}"

dmg-verify-stapled: dmg-staple
  just validate-stapled-file "{{release_dmg_file}}"
  spctl -a -t open --context context:primary-signature -v "{{release_dmg_file}}"

install-release:
  ditto "{{app_file}}" "{{installed_app_file}}"

verify-installed:
  codesign --verify --deep --strict --verbose=4 "{{installed_app_file}}"
  codesign --verify --strict --verbose=4 "{{installed_helper_file}}"
  plutil -p "{{installed_app_file}}/Contents/Library/LaunchDaemons/FanControlHelper.plist"

dist-zip: zip-release
dist: dist-zip
dist-dmg: dmg-verify-stapled
