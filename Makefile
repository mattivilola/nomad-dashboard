APP_NAME := NomadDashboard
SCHEME := NomadDashboard
PROJECT := $(APP_NAME).xcodeproj

.PHONY: bootstrap generate build test lint archive dmg release-dry-run clean

bootstrap:
	./scripts/bootstrap.sh

generate:
	./scripts/generate-project.sh

build:
	./scripts/build-dev.sh

test:
	./scripts/test.sh

lint:
	./scripts/lint.sh

archive:
	./scripts/archive-release.sh

dmg:
	./scripts/create-dmg.sh

release-dry-run:
	./scripts/sign-and-notarize.sh --dry-run
	./scripts/publish-update.sh --dry-run

clean:
	rm -rf .build DerivedData

