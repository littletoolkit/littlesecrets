REQUIRE_BIN=pandoc

.PHONY: all
all: test test docs
	@

.PHONY: test
test:
	@bash tests/harness.sh

define sh-install
	PREFIX="$(if $(PREFIX),$(PREFIX),$(if $(HOME),$(HOME)/.local,/usr/local))"
	if [ -z "$$PREFIX" ]; then
		echo "!!! ERR: PREFIX is undefined"
		exit 1
	else
		echo "... Installing under: $$PREFIX"
	fi
	mkdir -p "$$PREFIX/bin"
	$1 src/sh/littlesecrets.sh "$$PREFIX/bin/littlesecrets"
	echo "-> Installed $2 $$PREFIX/bin/littlesecrets"
	mkdir -p "$$PREFIX/share/man/man1"
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

.PHONY: compile
compile: dist/littlesecrets
	@

dist/littlesecrets: $(wildcard src/sh/*.sh)
	@mkdir -p $(dir $@)
	mkdir -p build
	for file in $^; do cp -a "$$file" build; done;
	echo "#!$$(which bash)" > "build/$(notdir $<)"
	tail -n +2 "$<" >> "build/$(notdir $<)"
	shc -U -f "build/$(notdir $<)" -o "$@"

dist/docs/manual.html: docs/manual.md
	@mkdir -p $(dir $@)
	cp docs/style.css $(dir $@)/
	if ! which pandoc 2> /dev/null; then
		echo "!!! ERR Cannot find 'pandoc'"
		exit 1
	fi
	pandoc docs/manual.md -s --toc -c style.css -o "$@"

dist/docs/littlesecrets.1:
	@mkdir -p "$(dir $@)"
	if ! which pandoc 2> /dev/null; then
		echo "!!! ERR Cannot find 'pandoc'"
		exit 1
	fi
	pandoc docs/manual.md -s -t man -o "$@"

.ONESHELL:

# EOF
