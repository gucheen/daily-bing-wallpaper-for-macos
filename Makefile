.PHONY: build install run test

build:
	python3 scripts/build.py

install: build
	mkdir -p "$(HOME)/Applications"
	ditto "build/Daily Wallpaper.app" "$(HOME)/Applications/Daily Wallpaper.app"

run: build
	open "build/Daily Wallpaper.app"

test:
	@output=$$(mktemp -d); \
	trap 'rm -rf "$$output"' EXIT; \
	swiftc -parse-as-library -D WALLPAPER_TESTING \
		DailyWallpaper.swift Tests/WallpaperStoreTests.swift \
		-framework AppKit -framework CoreImage \
		-o "$$output/tests" && "$$output/tests"
