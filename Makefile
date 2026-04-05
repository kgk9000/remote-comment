.PHONY: help build capture display lint clean

.DEFAULT_GOAL := help

## help: Show this help message
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //' | column -t -s ':'

## build: Build both targets
build:
	swift build -c release

## capture: Build and run the capture side (laptop)
capture: build
	.build/release/Capture $(ARGS)

## display: Build and run the display side (Mac Mini)
display: build
	.build/release/Display $(ARGS)

## lint: Check for warnings and errors
lint:
	swift build 2>&1 | grep -E 'warning:|error:' || echo "No warnings or errors"

## clean: Remove build artifacts
clean:
	swift package clean
	rm -rf .build
