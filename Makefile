SHELL := /bin/bash

APP_NAME := Budget AI
APK_OUTPUT := build/app/outputs/flutter-apk/app-release.apk
DOCUMENTS_DIR := $(HOME)/Documents/$(APP_NAME)
KEYSTORE_FILE := $(HOME)/Keystores/budgetai.jks
KEY_ALIAS := key0
STORE_PASSWORD := admin123
KEY_PASSWORD := admin123

.DEFAULT_GOAL := help

.PHONY: help apk clean verify-signing

help:
	@printf "Available commands:\n"
	@printf "\n"
	@printf "  apk    Build a signed arm64 APK and copy it to ~/Documents/$(APP_NAME)/\n"
	@printf "  clean  Run flutter clean\n"
	@printf "  verify-signing  Check the Budget AI release keystore\n"
	@printf "\n"

apk:
	@if [ ! -f "$(KEYSTORE_FILE)" ]; then \
		printf "Creating release keystore: $(KEYSTORE_FILE)\n"; \
		mkdir -p "$$(dirname "$(KEYSTORE_FILE)")"; \
		keytool -genkeypair -v \
			-keystore "$(KEYSTORE_FILE)" \
			-storepass "$(STORE_PASSWORD)" \
			-keypass "$(KEY_PASSWORD)" \
			-keyalg RSA \
			-keysize 2048 \
			-validity 10000 \
			-alias "$(KEY_ALIAS)" \
			-dname "CN=Budget AI, OU=Budget AI, O=Budget AI, L=Unknown, ST=Unknown, C=US"; \
	fi
	@printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
		"$(KEYSTORE_FILE)" "$(STORE_PASSWORD)" "$(KEY_ALIAS)" "$(KEY_PASSWORD)" \
		> android/key.properties
	@flutter build apk --release --target-platform android-arm64; status=$$?; \
	rm -f android/key.properties; \
	exit $$status
	@version=$$(awk '/^version:[[:space:]]*/ { print $$2; exit }' pubspec.yaml); \
	dest="$(DOCUMENTS_DIR)"; \
	mkdir -p "$$dest"; \
	cp "$(APK_OUTPUT)" "$$dest/$(APP_NAME) $$version.apk"; \
	printf "APK ready: $$dest/$(APP_NAME) $$version.apk\n"

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
