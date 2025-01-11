# Default target
.PHONY: all
all: test

# Run all tests
.PHONY: test
test:
	bun test tests/*.js

# Generate test keys
.PHONY: test-keys
test-keys:
	bun tests/data/generate-test-keys.js

# Clean generated test files
.PHONY: clean
clean:
	rm -f tests/data/keypair.*.pub tests/data/keypair.*.priv

.ONESHELL:
# EOF
