BINARY  = vaelja
SOURCE  = vaelja.swift
PREFIX ?= /usr/local/bin

.PHONY: build install uninstall clean

build:
	swiftc -O -o $(BINARY) $(SOURCE)

install: build
	install -d $(PREFIX)
	install -m 755 $(BINARY) $(PREFIX)/$(BINARY)

uninstall:
	rm -f $(PREFIX)/$(BINARY)
	rm -f ~/Library/LaunchAgents/com.vaelja.plist

clean:
	rm -f $(BINARY)
