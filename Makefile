APP_NAME := DeepSeek Peak
BUNDLE := dist/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
INSTALLED := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: build app run test install uninstall dump icon clean

build:
	swift build -c release

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "$(BUNDLE)"

install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED)"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"
	open "$(INSTALLED)"

uninstall:
	-pkill -x DeepSeekPeak 2>/dev/null
	rm -rf "$(INSTALLED)"
	@echo "Removed $(INSTALLED)"

dump: build
	./.build/release/DeepSeekPeakBar --dump --days 14

icon:
	python3 scripts/make-icon.py

clean:
	swift package clean
	rm -rf dist
