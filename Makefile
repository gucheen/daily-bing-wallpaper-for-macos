build:
	swiftc -parse-as-library \
		DailyWallpaper.swift \
		-framework AppKit \
		-o "daily-wallpaper"

install:
	mkdir -p ~/.local/bin
	cp daily-wallpaper ~/.local/bin/