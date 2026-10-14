SHELL := /bin/bash

APP_NAME := Budget AI
APK_OUTPUT := build/app/outputs/flutter-apk/app-release.apk
AAB_OUTPUT := build/app/outputs/bundle/release/app-release.aab
DOCUMENTS_DIR := $(HOME)/Documents/$(APP_NAME)

# Play upload key. The keystore and a backup of its key.properties values
# live outside the repo; android/key.properties is gitignored.
KEYSTORE_FILE := $(HOME)/Muzamil/Keystores/budget-ai.keystore
KEYSTORE_PROPS_BACKUP := $(HOME)/Muzamil/Keystores/budget-ai-key.properties.txt
KEY_PROPERTIES := android/key.properties

WEBSITE_DIR := website
PAGES_PROJECT := budgetai-app
PAGES_URL := https://$(PAGES_PROJECT).pages.dev

.DEFAULT_GOAL := help

.PHONY: help apk apk-split aab clean verify-signing signing \
	web-install web-dev web-build web-preview web-deploy

help:
	@printf "Available commands:\n"
	@printf "\n"
	@printf "  App\n"
	@printf "    apk             Build a signed arm64 APK and copy it to ~/Documents/$(APP_NAME)/\n"
	@printf "    apk-split       Build split-per-abi APKs (smaller per-device) and copy them\n"
	@printf "    aab             Build the signed Play App Bundle and copy it\n"
	@printf "    verify-signing  Check the Play upload keystore and key.properties\n"
	@printf "    clean           Run flutter clean\n"
	@printf "\n"
	@printf "  Website ($(PAGES_URL))\n"
	@printf "    web-dev         Run the site locally at http://localhost:4321\n"
	@printf "    web-build       Build the site into $(WEBSITE_DIR)/dist\n"
	@printf "    web-preview     Serve the built site locally\n"
	@printf "    web-deploy      Build and publish the site to Cloudflare Pages\n"
	@printf "\n"

# Writes android/key.properties from the keystore backup when it is missing,
# so a fresh clone can sign release builds. Never deleted afterwards.
signing:
	@if [ ! -f "$(KEYSTORE_FILE)" ]; then \
		printf "Missing keystore: $(KEYSTORE_FILE)\n"; \
		printf "Restore budget-ai.keystore from your backup first.\n"; \
		exit 1; \
	fi
	@if [ ! -f "$(KEY_PROPERTIES)" ]; then \
		if [ ! -f "$(KEYSTORE_PROPS_BACKUP)" ]; then \
			printf "Missing $(KEY_PROPERTIES) and backup $(KEYSTORE_PROPS_BACKUP)\n"; \
			exit 1; \
		fi; \
		grep -E '^(storePassword|keyPassword|keyAlias|storeFile)=' "$(KEYSTORE_PROPS_BACKUP)" > "$(KEY_PROPERTIES)"; \
		chmod 600 "$(KEY_PROPERTIES)"; \
		printf "Created $(KEY_PROPERTIES) from the keystore backup\n"; \
	fi

apk: signing
	@flutter build apk --release --target-platform android-arm64 \
		--split-debug-info=build/debug-info --obfuscate || exit $$?; \
	version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; mkdir -p "$$dest"; \
	cp "$(APK_OUTPUT)" "$$dest/$(APP_NAME) $$version.apk"; \
	printf "APK ready: $$dest/$(APP_NAME) $$version.apk\n"

apk-split: signing
	@flutter build apk --release --split-per-abi \
		--split-debug-info=build/debug-info --obfuscate || exit $$?; \
	version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; mkdir -p "$$dest"; \
	for apk in build/app/outputs/flutter-apk/app-*-release.apk; do \
		abi=$$(basename "$$apk" | sed 's/app-\(.*\)-release.apk/\1/'); \
		cp "$$apk" "$$dest/$(APP_NAME) $$version ($$abi).apk"; \
		printf "APK ready: $$dest/$(APP_NAME) $$version ($$abi).apk\n"; \
	done

aab: signing
	@flutter build appbundle --release \
		--split-debug-info=build/debug-info --obfuscate || exit $$?; \
	version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; mkdir -p "$$dest"; \
	cp "$(AAB_OUTPUT)" "$$dest/$(APP_NAME) $$version.aab"; \
	printf "AAB ready: $$dest/$(APP_NAME) $$version.aab\n"; \
	keytool -printcert -jarfile "$(AAB_OUTPUT)" 2>/dev/null | grep -m1 "SHA256" | sed 's/^/Signed with /'

clean:
	@flutter clean

verify-signing: signing
	@pass=$$(sed -n 's/^storePassword=//p' "$(KEY_PROPERTIES)"); \
	alias=$$(sed -n 's/^keyAlias=//p' "$(KEY_PROPERTIES)"); \
	keytool -list -keystore "$(KEYSTORE_FILE)" -storepass "$$pass" -alias "$$alias" >/dev/null \
		&& printf "Play upload keystore is ready: $(KEYSTORE_FILE) (alias $$alias)\n"

# --- Website (Cloudflare Pages) ---

web-install:
	@cd "$(WEBSITE_DIR)" && if [ ! -d node_modules ]; then npm install; fi

web-dev: web-install
	@cd "$(WEBSITE_DIR)" && npm run dev

web-build: web-install
	@cd "$(WEBSITE_DIR)" && npm run build

web-preview: web-build
	@cd "$(WEBSITE_DIR)" && npm run preview

web-deploy: web-build
	@cd "$(WEBSITE_DIR)" && npx --yes wrangler@4 pages deploy dist \
		--project-name "$(PAGES_PROJECT)" --branch master --commit-dirty=true
	@printf "Live at $(PAGES_URL)\n"
