CC = zig
BIN = check-tsp
PREFIX?=/usr/local
BINDIR?=$(PREFIX)/bin

all: $(BIN)

$(BIN):
	@$(CC) build
	@./zig-out/bin/$@ tests
.PHONY: $(BIN)

install: $(BIN)
	cp ./zig-out/bin/$(BIN)  $(BINDIR)/
