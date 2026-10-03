# WaitList — build without Xcode. Requires Command Line Tools (Swift 5.10+).
.PHONY: build app run stop test icon release clean

CONFIG ?= release
APP = build/WaitList.app

build:            ## Compile with SwiftPM
	swift build -c $(CONFIG)

app:              ## Assemble $(APP)
	Packaging/build-app.sh $(CONFIG)

run: stop app     ## Build and launch the app
	open $(APP)

stop:             ## Quit a running WaitList
	-pkill -x WaitList 2>/dev/null; true

test:             ## Run unit tests
	swift test

icon:             ## Regenerate app icon + menubar glyphs from Tools/
	swift Tools/make-icon.swift

release: app      ## Zip for distribution
	cd build && rm -f WaitList.zip && ditto -c -k --keepParent WaitList.app WaitList.zip && echo "build/WaitList.zip"

clean:
	rm -rf .build build
