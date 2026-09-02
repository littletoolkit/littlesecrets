--
Id: SEC-14
Title: Key Material Leaked to Kernel/Audit Logs via File Existence Checks (MEDIUM)
Location: src/sh/littlesecrets.sh:745, 840
--

Lines 745 and 840 check whether key material passed in a variable is a file path using `[ -e "$1" ]` or `[ ! -f "$file" ]`.
- Impact:
When raw key material (such as an SSH public key string or PEM block) is supplied as an argument, `[ -e "$1" ]` issues a stat(2) system call with the key content as the path. This leaks key material into kernel audit logs (auditd records failed stat paths), strace traces, and system monitoring tools.
- Remediation:
Check whether the argument contains whitespace or newline characters before testing for file existence, or use a distinct flag/prefix to distinguish key contents from file paths.
