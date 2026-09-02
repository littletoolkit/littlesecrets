--
Id: SEC-01
Title: Shell Command Injection via Unescaped Secret Values in export (CRITICAL)
Location: src/sh/littlesecrets.sh:1978–1995
--

The export command generates shell export assignments intended to be executed with eval "$(littlesecrets export)":
1987: echo "export $envname= # ERROR: Secret HMAC invalid"
1993: echo "export $envname='${secval}'"
Neither $envname nor ${secval} is sanitized or escaped.
- Impact:
If a secret value contains a single quote followed by shell commands (e.g., test'; id; echo '), running eval $(littlesecrets export) results in immediate arbitrary code execution. Furthermore, if $var has an unvalidated envname (e.g., MALICIOUS$(id)=secret), the variable name itself executes arbitrary code.
- Remediation:
1. Validate $envname against a strict identifier regex: ^[_a-zA-Z][_a-zA-Z0-9]*$.
2. Safely quote values using Bash's printf '%q' or by escaping single quotes:
printf 'export %s=%q\n' "$envname" "$secval"
