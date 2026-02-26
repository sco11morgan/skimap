VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "0.1.0")
SCHEME  := Skimap
PROJECT := Skimap.xcodeproj
ARCHIVE := build/Skimap.xcarchive
APP     := build/export/Skimap.app
ZIP     := build/Skimap-$(VERSION).zip

# ── Build targets ─────────────────────────────────────────────────────────────

.PHONY: release archive export zip clean

## Build, package, and publish a GitHub release.
## Usage:  make release VERSION=1.2.0
release: zip
	gh release create "v$(VERSION)" "$(ZIP)" \
		--title "Skimap v$(VERSION)" \
		--generate-notes
	@echo "✅  Released Skimap v$(VERSION)"

## Create a .zip ready for upload (without publishing).
zip: export
	cd build/export && zip -r --symlinks "../../$(ZIP)" Skimap.app
	@echo "📦  Created $(ZIP)"

## Export the .app from the archive.
export: archive
	xcodebuild -exportArchive \
		-archivePath "$(ARCHIVE)" \
		-exportPath build/export \
		-exportOptionsPlist ExportOptions.plist

## Archive the project (Release configuration).
archive:
	mkdir -p build
	xcodebuild archive \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "generic/platform=macOS" \
		-configuration Release \
		-archivePath "$(ARCHIVE)"

## Remove all build artefacts.
clean:
	rm -rf build
