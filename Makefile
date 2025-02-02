.PHONY: all
all: test-keys test docs

.PHONY: test
test:
	bun test ./tests/*.js

define sh-install
	PREFIX="$(if $(HOME),$(HOME)/.local,/usr/local)"
	mkdir -p "$$PREFIX/bin"
	$1 src/sh/littlesecrets.sh "$$PREFIX/bin/littlesecrets"
	echo "-> Installed $2 $$PREFIX/bin/littlesecrets"
	mkdir -p "$$PREFIX/share/man1"
	$1 dist/docs/littlesecrets.1 "$$PREFIX/share/man/man1/littlesecrets.1"
	echo "-> Installed $2 $$PREFIX/share/man/man1/littlesecrets.1"
endef

.PHONY: install-link
install-link: dist/docs/littlesecrets.1
	@$(call sh-install,ln -sfr,(link))

.PHONY: install
install: dist/docs/littlesecrets.1
	@$(call sh-install,cp -a,(copy))

.PHONY: docs
docs: dist/docs/manual.html dist/docs/littlesecrets.1
	@

dist/docs/manual.html: docs/manual.md
	@mkdir -p $(dir $@)
	cp docs/style.css $(dir $@)/
	pandoc docs/manual.md -s --toc -c style.css -o "$@"

dist/docs/littlesecrets.1:
	@mkdir -p "$(dir $@)"
	pandoc docs/manual.md -s -t man -o "$@"

.ONESHELL:

# EOF
