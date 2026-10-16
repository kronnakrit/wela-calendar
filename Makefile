PACKAGES := Packages/WelaCore Packages/WelaSync Packages/WelaUI
XCB := xcodebuild -project Wela.xcodeproj -scheme Wela -destination 'platform=macOS' \
	-derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO

.PHONY: bootstrap gen build test lint run

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
	swift-format lint --strict --recursive App AppTests Packages/*/Sources Packages/*/Tests

run: build
	open DerivedData/Build/Products/Debug/Wela.app --args -UseMockData
