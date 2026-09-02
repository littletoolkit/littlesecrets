--
Id: SEC-05
Title: Command Injection Risk via Unsanitized eval in Error & Cleanup Traps (HIGH)
Location: src/sh/littlesecrets.sh:258–260, 375–377, 2695
--

LS_TRAP_PREVIOUS="$(trap -p EXIT INT TERM | cut -d"'" -f2 | sort | uniq)"
...
eval "$LS_TRAP_PREVIOUS"
The script captures existing signal handlers with trap -p and parses them using cut -d"'" -f2, assuming simple single-quoted strings.
- Impact:
If an existing trap in the calling environment has internal quotes, semicolons, or multiline commands, cut -d"'" -f2 produces corrupted strings, and executing eval on it can trigger unintended commands or syntax errors.
- Remediation:
Avoid slicing and re-evaluating trap strings. If preserving traps is necessary, save and restore them per signal without string splitting or eval.
