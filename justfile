set dotenv-load := true

app_file := "build/macos/Build/Products/Release/MacFanTool.app"

default:
  just --list

build:
  flutter build macos --release

test:
  flutter test

format:
  dart format .

analyze:
  flutter analyze

icon:
  dart run flutter_launcher_icons

sign:
  codesign --force --deep --strict --verbose --timestamp \
    --entitlements=macos/Runner/Release.entitlements \
    --options=runtime --sign "${APPLE_SIGN_NAME}" {{app_file}}

verify:
  codesign --verify --deep --strict --verbose=4 {{app_file}}
  spctl --assess --verbose {{app_file}}
  codesign -d --entitlements - {{app_file}}

zip:
  ditto -c -k --sequesterRsrc --keepParent \
    "{{app_file}}" \
    "MacFanTool.zip"

notary:
  xcrun notarytool submit MacFanTool.zip \
    --apple-id "${APPLE_EMAIL_ADDRESS}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APP_SPECIFIC_PASSWORD}" \
    --wait

staple:
  xcrun stapler staple {{app_file}}

all:
  just build && just sign && just verify && just zip && just notary && just staple
