APP_NAME=WeReadDrawer

all: build

build:
	@./build.sh

run: build
	@open "build/$(APP_NAME).app"

clean:
	@rm -rf build

.PHONY: all build run clean
