In order to secure our shell commands, we want to avoid to:
- store secrets on the file system (even in 600 mode files),
- leak secrets through the environment
- leak secrets through `/proc` (harder)

You can see more [details here](https://stackoverflow.com/questions/3830823/hiding-secret-from-command-line-parameter-on-unix).

Here are some rules to avoid that:
- Use the built-in `printf` instead of `echo` to pass values through stdin
- Use file descriptors like `exec 3<<<$(...)` to store files outside of the filesystem
- Use key derivation or hashing as a last resort when passing to the
