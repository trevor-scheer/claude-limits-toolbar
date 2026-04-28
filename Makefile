.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh

run: app
	open "dist/Claude Limits.app"

clean:
	rm -rf .build dist
