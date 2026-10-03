# WaitList — build without Xcode. Requires Command Line Tools (Swift 5.10+).
.PHONY: build app run stop install test icon release clean

CONFIG ?= release
APP = build/WaitList.app

build:            ## Compile with SwiftPM
	swift build -c $(CONFIG)

app:              ## Assemble $(APP); UNIVERSAL=1 builds arm64 + x86_64 (needs Xcode)
	Packaging/build-app.sh $(CONFIG)

run: stop app     ## Build and launch the app
	open $(APP)

stop:             ## Quit a running WaitList
	-pkill -x WaitList 2>/dev/null; true

install: stop app ## Build a release bundle, copy it to /Applications and launch it
	rm -rf /Applications/WaitList.app
	ditto $(APP) /Applications/WaitList.app
	open /Applications/WaitList.app

test:             ## Run unit tests
	swift test

icon:             ## Regenerate app icon + menubar glyphs (Resources/) and Screenshots/icon.png from Tools/
	swift Tools/make-icon.swift

release: app      ## Zip for distribution
	cd build && rm -f WaitList.zip && ditto -c -k --keepParent WaitList.app WaitList.zip && echo "build/WaitList.zip"

clean:
	rm -rf .build build
