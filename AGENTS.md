# Agent Guidelines for LittleSecrets

## Build/Test Commands
- `make test` - Run all tests
- `make check` - Run shellcheck linting on all .sh files
- `bash tests/harness.sh tests/T001-cli-crypto.sh` - Run single test (replace T001 with desired test)
- `make docs` - Generate documentation (requires pandoc)
- `make clean` - Clean build artifacts

## Code Style Guidelines
- **Shell scripts**: Use `#!/usr/bin/env bash`, `set -euo pipefail`, `shopt -s extglob`
- **Naming**: 
  - Globals: `UPPER_CASE`
  - Functions/parameters: `camelCase`
  - Local variables: `snake_case`
  - Classes/Types: `PascalCase`
- **Style**: Write concise, compact code with minimal comments. Use short docstrings.
- **Dependencies**: Favor standard library, minimize third-party dependencies
- **Error handling**: Always use `set -euo pipefail` for robust error handling
- **Testing**: All test files follow `T###-description.sh` pattern in tests/ directory

## Project Structure
- Main CLI: `src/sh/littlesecrets.sh`
- Tests: `tests/T*.sh` with harness in `tests/harness.sh`
- Documentation: `docs/manual.md` (generates man page and HTML)
- Specs: `docs/spec/spec-*.md` for technical specifications