CC = zig
BIN = check-tsp

all: $(BIN)

$(BIN):
	@$(CC) build
	@./zig-out/bin/$@ tests
.PHONY: $(BIN)
