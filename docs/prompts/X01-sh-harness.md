Can you write me a shell (bash) library with the following functions:

- `LOG <MESSAGE?>` that print the given message on stderr
- `DO <COMMAND>` that runs the `COMMAND` (which should be given as a quoted string) and prints `OK` if it succeeds
  or `FAIL <COMMAND>` if it fails and stops the script.
- `MKTEMP <PREFIX?> <SUFFIX?>` that creates a temporary file and automatically removes it on exit
- `MKDTEMP <PREFIX?> <SUFFIX?>` that creates a temporary directory and automatically removes it recursively on exit
- `NOEMPTY <PATH>` that fails if PATH is not a file or is empty
