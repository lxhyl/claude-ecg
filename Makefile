.PHONY: build run test app clean

build:
	swift build -c release

run: build
	./.build/release/ECGBar

test:
	swift test

app:
	./scripts/build-app.sh

clean:
	rm -rf .build build
