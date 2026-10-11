.PHONY: build test generate open clean app

build:
	swift build

test:
	swift test

generate:
	cd App && xcodegen generate

open: generate
	open App/TPApp.xcodeproj

clean:
	swift package clean
	rm -rf App/TPApp.xcodeproj

# Builds the macOS app (ad-hoc signed, runs without a paid Apple Developer account),
# installs it to /Applications and launches it.
app: generate
	cd App && xcodebuild -project TPApp.xcodeproj -scheme TPApp-macOS -configuration Release \
		-derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES build
	rm -rf /Applications/TPCloud.app
	cp -R App/build/Build/Products/Release/TPApp-macOS.app /Applications/TPCloud.app
	open /Applications/TPCloud.app
