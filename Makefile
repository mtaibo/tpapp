.PHONY: build test generate open clean

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
