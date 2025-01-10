.PHONY: test clean

# Default target
all: test

# Run all tests
test:
	zig test src/zig/rsa.zig
	@echo "All tests completed"

# Clean build artifacts 
clean:
	rm -rf zig-cache/
	rm -rf zig-out/
