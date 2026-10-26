PACKAGES := Packages/WelaCore Packages/WelaSync Packages/WelaUI
XCB := xcodebuild -project Wela.xcodeproj -scheme Wela -destination 'platform=macOS' \
	-derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO

.PHONY: bootstrap gen build test lint run ios-build ios-screenshots ios-archive ios-upload

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v swift-format >/dev/null || brew install swift-format
	@test -f Config/Secrets.xcconfig || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig

gen:
	xcodegen generate

build: gen
	$(XCB) build

test: gen
	@for p in $(PACKAGES); do swift test --package-path $$p || exit 1; done
	$(XCB) test

lint:
	@if grep -rEn "^import (UIKit|AppKit|SwiftUI)" Packages/WelaCore/Sources; then \
		echo "WelaCore must not import UI frameworks"; exit 1; fi
	swift-format lint --strict --recursive App AppTests iOS Packages/*/Sources Packages/*/Tests

run: build
	open DerivedData/Build/Products/Debug/Wela.app --args -UseMockData

# iOS (iPhone + iPad app and widgets). See docs/IOS.md for signing and TestFlight.
IOS_XCB := xcodebuild -project Wela.xcodeproj -scheme WelaiOS -derivedDataPath DerivedData

ios-build: gen
	$(IOS_XCB) -configuration Debug -destination 'generic/platform=iOS Simulator' \
		CODE_SIGNING_ALLOWED=NO build

ios-screenshots: ios-build
	scripts/ios-screenshots.sh DerivedData/Build/Products/Debug-iphonesimulator/Wela.app screenshots

# Needs DEVELOPMENT_TEAM in Config/Secrets.xcconfig and an Xcode account signed in to that team.
ios-archive: gen
	$(IOS_XCB) -configuration Release -destination 'generic/platform=iOS' \
		-archivePath build/Wela-iOS.xcarchive -allowProvisioningUpdates archive

# Uploads the archive to App Store Connect; it shows up in TestFlight after processing.
ios-upload: ios-archive
	xcodebuild -exportArchive -archivePath build/Wela-iOS.xcarchive \
		-exportOptionsPlist iOS/ExportOptions.plist -exportPath build/ios-export \
		-allowProvisioningUpdates
