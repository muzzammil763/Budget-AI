SHELL := /bin/bash

APP_NAME := Budget AI
APK_OUTPUT := build/app/outputs/flutter-apk/app-release.apk
DOCUMENTS_DIR := $(HOME)/Documents/$(APP_NAME)

.DEFAULT_GOAL := help

.PHONY: help apk clean

help:
	@printf "Available commands:\n"
	@printf "\n"
	@printf "  apk    Build an arm64 release APK and copy it to ~/Documents/$(APP_NAME)/\n"
	@printf "  clean  Run flutter clean\n"
	@printf "\n"

apk:
	@flutter build apk --release --target-platform android-arm64
	@version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; \
	mkdir -p "$$dest"; \
	cp "$(APK_OUTPUT)" "$$dest/$(APP_NAME) $$version.apk"; \
	printf "APK ready: $$dest/$(APP_NAME) $$version.apk\n"

clean:
	@flutter clean
