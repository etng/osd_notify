PREFIX ?= $(HOME)/.local
DESTDIR ?=
MESSAGE ?= 任务完成
ARCH := $(shell uname -m)
BINARY := .build/release/osd-notify
ARCHIVE := osd-notify-macos-$(ARCH).tar.gz

.DEFAULT_GOAL := all

.PHONY: all
all: run

.PHONY: build
build:
	swift build --configuration release --disable-automatic-resolution

.PHONY: package
package: build
	mkdir -p dist
	tar -czf "dist/$(ARCHIVE)" -C "$(dir $(BINARY))" "$(notdir $(BINARY))"
	cd dist && shasum -a 256 "$(ARCHIVE)" > "$(ARCHIVE).sha256"

.PHONY: install
install: package
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 755 "$(BINARY)" "$(DESTDIR)$(PREFIX)/bin/osd-notify"

.PHONY: run
run: install
	"$(DESTDIR)$(PREFIX)/bin/osd-notify" show "$(MESSAGE)" --level done --ttl 60
