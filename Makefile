# Default target
.PHONY: all
all: test-keys test docs

# Documentation directories
DOCS_DIR = dist/docs
MAN_DIR = dist/share/man/man1

# Run all tests
.PHONY: test
test:
	bun test ./tests/*.js

# Generate test keys
.PHONY: test-keys
test-keys:
	mkdir -p tests/data
	bun tests/data/generate-test-keys.js

# Generate documentation
.PHONY: docs
docs: html man

.PHONY: html
html: $(DOCS_DIR)
	mkdir -p $(DOCS_DIR)
	cp docs/style.css $(DOCS_DIR)/
	pandoc docs/manual.md -s --toc -c style.css -o $(DOCS_DIR)/manual.html

.PHONY: man
man: $(MAN_DIR)
	mkdir -p $(MAN_DIR)
	pandoc docs/manual.md -s -t man -o $(MAN_DIR)/littlesecrets.1

# Clean generated test files and documentation
.PHONY: clean
clean:
	rm -f tests/data/keypair.*.pub tests/data/keypair.*.priv
	rm -rf dist

.ONESHELL:
# EOF
