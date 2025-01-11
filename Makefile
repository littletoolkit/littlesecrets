# Default target
.PHONY: all
all: test-keys test

# Run all tests
.PHONY: test
test:
	bun test ./tests/*.js

# Generate test keys
.PHONY: test-keys
test-keys:
	mkdir -p tests/data
	bun tests/data/generate-test-keys.js

# Clean generated test files
.PHONY: clean
clean:
	rm -f tests/data/keypair.*.pub tests/data/keypair.*.priv

.ONESHELL:
# EOF
