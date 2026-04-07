.PHONY: help build capture lint clean

.DEFAULT_GOAL := help

## help: Show this help message
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //' | column -t -s ':'

## build: Build the capture target
build:
	swift build -c release

## capture: Build and run capture (laptop side)
capture: build
	.build/release/Capture $(ARGS)

## lint: Check for warnings and errors
lint:
	swift build 2>&1 | grep -E 'warning:|error:' || echo "No warnings or errors"

## clean: Remove build artifacts
clean:
	swift package clean
	rm -rf .build
