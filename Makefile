export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

APP := build/Outlook2iCloudCal.app

.PHONY: test app install cert

test:
	swift test $(if $(FILTER),--filter '$(FILTER)')

app:
	scripts/build-app.sh

install: app
	mkdir -p $(HOME)/Applications
	ditto $(APP) $(HOME)/Applications/Outlook2iCloudCal.app
	open $(HOME)/Applications/Outlook2iCloudCal.app

cert:
	scripts/create-signing-identity.sh
