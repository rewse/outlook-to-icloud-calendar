export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

APP := build/Outlook2iCloudCal.app

.PHONY: test app dmg install cert release-patch release-minor release-major

test:
	swift test $(if $(FILTER),--filter '$(FILTER)')

app:
	scripts/build-app.sh

dmg: app
	scripts/build-dmg.sh

install: app
	mkdir -p $(HOME)/Applications
	ditto $(APP) $(HOME)/Applications/Outlook2iCloudCal.app
	open $(HOME)/Applications/Outlook2iCloudCal.app

cert:
	scripts/create-signing-identity.sh

release-patch:
	scripts/bump-version.sh patch --push

release-minor:
	scripts/bump-version.sh minor --push

release-major:
	scripts/bump-version.sh major --push
