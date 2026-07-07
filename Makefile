SHELL := /bin/bash

APP_NAME := Budget AI
APK_OUTPUT := build/app/outputs/flutter-apk/app-release.apk
AAB_OUTPUT := build/app/outputs/bundle/release/app-release.aab
DOCUMENTS_DIR := $(HOME)/Documents/$(APP_NAME)
KEYSTORE_FILE := $(HOME)/Keystores/budgetai.jks
KEY_ALIAS := key0
STORE_PASSWORD := admin123
KEY_PASSWORD := admin123

.DEFAULT_GOAL := help

.PHONY: help apk apk-split aab clean verify-signing

help:
	@printf "Available commands:\n"
	@printf "\n"
	@printf "  apk        Build a signed arm64 APK and copy it to ~/Documents/$(APP_NAME)/\n"
	@printf "  apk-split  Build split-per-abi APKs (smaller per-device) and copy them\n"
	@printf "  aab        Build a signed Android App Bundle and copy it\n"
	@printf "  clean      Run flutter clean\n"
	@printf "  verify-signing  Check the Budget AI release keystore\n"
	@printf "\n"
	@printf "Set DEEPSEEK_API_KEY ahead of time to skip the prompt:\n"
	@printf "  DEEPSEEK_API_KEY=sk-xxx make apk\n"
	@printf "\n"

apk:
	@key="$${DEEPSEEK_API_KEY:-}"; \
	if [ -z "$$key" ]; then read -p "Enter DeepSeek API key (will be baked into the APK): " key; fi; \
	if [ ! -f "$(KEYSTORE_FILE)" ]; then \
		printf "Creating release keystore: $(KEYSTORE_FILE)\n"; \
		mkdir -p "$$(dirname "$(KEYSTORE_FILE)")"; \
		keytool -genkeypair -v \
			-keystore "$(KEYSTORE_FILE)" \
			-storepass "$(STORE_PASSWORD)" \
			-keypass "$(KEY_PASSWORD)" \
			-keyalg RSA \
			-keysize 2044 \
			-validity 10000 \
			-alias "$(KEY_ALIAS)" \
			-dname "CN=Budget AI, OU=Budget AI, O=Budget AI, L=Unknown, ST=Unknown, C=US"; \
	fi; \
	printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
		"$(KEYSTORE_FILE)" "$(STORE_PASSWORD)" "$(KEY_ALIAS)" "$(KEY_PASSWORD)" \
		> android/key.properties; \
	printf "Building with DeepSeek API key\n"; \
	flutter build apk --release --target-platform android-arm64 \
		--split-debug-info=build/debug-info --obfuscate \
		--dart-define=DEEPSEEK_API_KEY=$$key; \
	status=$$?; rm -f android/key.properties; [ $$status -ne 0 ] && exit $$status; \
	version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; mkdir -p "$$dest"; \
	cp "$(APK_OUTPUT)" "$$dest/$(APP_NAME) $$version.apk"; \
	printf "APK ready: $$dest/$(APP_NAME) $$version.apk\n"

apk-split:
	@key="$${DEEPSEEK_API_KEY:-}"; \
	if [ -z "$$key" ]; then read -p "Enter DeepSeek API key (will be baked into the APK): " key; fi; \
	if [ ! -f "$(KEYSTORE_FILE)" ]; then \
		printf "Creating release keystore: $(KEYSTORE_FILE)\n"; \
		mkdir -p "$$(dirname "$(KEYSTORE_FILE)")"; \
		keytool -genkeypair -v \
			-keystore "$(KEYSTORE_FILE)" \
			-storepass "$(STORE_PASSWORD)" \
			-keypass "$(KEY_PASSWORD)" \
			-keyalg RSA \
			-keysize 2044 \
			-validity 10000 \
			-alias "$(KEY_ALIAS)" \
			-dname "CN=Budget AI, OU=Budget AI, O=Budget AI, L=Unknown, ST=Unknown, C=US"; \
	fi; \
	printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
		"$(KEYSTORE_FILE)" "$(STORE_PASSWORD)" "$(KEY_ALIAS)" "$(KEY_PASSWORD)" \
		> android/key.properties; \
	printf "Building with DeepSeek API key\n"; \
	flutter build apk --release --split-per-abi \
		--split-debug-info=build/debug-info --obfuscate \
		--dart-define=DEEPSEEK_API_KEY=$$key; \
	status=$$?; rm -f android/key.properties; [ $$status -ne 0 ] && exit $$status; \
	version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; mkdir -p "$$dest"; \
	for apk in build/app/outputs/flutter-apk/app-*-release.apk; do \
		abi=$$(basename "$$apk" | sed 's/app-\(.*\)-release.apk/\1/'); \
		cp "$$apk" "$$dest/$(APP_NAME) $$version ($$abi).apk"; \
		printf "APK ready: $$dest/$(APP_NAME) $$version ($$abi).apk\n"; \
	done

aab:
	@key="$${DEEPSEEK_API_KEY:-}"; \
	if [ -z "$$key" ]; then read -p "Enter DeepSeek API key (will be baked into the APK): " key; fi; \
	if [ ! -f "$(KEYSTORE_FILE)" ]; then \
		printf "Creating release keystore: $(KEYSTORE_FILE)\n"; \
		mkdir -p "$$(dirname "$(KEYSTORE_FILE)")"; \
		keytool -genkeypair -v \
			-keystore "$(KEYSTORE_FILE)" \
			-storepass "$(STORE_PASSWORD)" \
			-keypass "$(KEY_PASSWORD)" \
			-keyalg RSA \
			-keysize 2044 \
			-validity 10000 \
			-alias "$(KEY_ALIAS)" \
			-dname "CN=Budget AI, OU=Budget AI, O=Budget AI, L=Unknown, ST=Unknown, C=US"; \
	fi; \
	printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
		"$(KEYSTORE_FILE)" "$(STORE_PASSWORD)" "$(KEY_ALIAS)" "$(KEY_PASSWORD)" \
		> android/key.properties; \
	printf "Building with DeepSeek API key\n"; \
	flutter build appbundle --release \
		--split-debug-info=build/debug-info --obfuscate \
		--dart-define=DEEPSEEK_API_KEY=$$key; \
	status=$$?; rm -f android/key.properties; [ $$status -ne 0 ] && exit $$status; \
	version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; mkdir -p "$$dest"; \
	cp "$(AAB_OUTPUT)" "$$dest/$(APP_NAME) $$version.aab"; \
	printf "AAB ready: $$dest/$(APP_NAME) $$version.aab\n"

clean:
	@flutter clean

verify-signing:
	@if [ ! -f "$(KEYSTORE_FILE)" ]; then \
		printf "Missing keystore: $(KEYSTORE_FILE)\n"; \
		exit 1; \
	fi
	@keytool -list \
		-keystore "$(KEYSTORE_FILE)" \
		-storepass "$(STORE_PASSWORD)" \
		-alias "$(KEY_ALIAS)" \
		>/dev/null
	@printf "Budget AI signing keystore is ready: $(KEYSTORE_FILE)\n"
