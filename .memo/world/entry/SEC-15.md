--
Id: SEC-15
Title: Unportable and Faulty Binary Detection (MEDIUM)
Location: src/sh/littlesecrets.sh:532–535
--

function ls_is_binary_file:
if LC_ALL=C grep -qP '[\x00-\x08\x0B\x0C\x0E-\x1F\x80-\xFF]' "$path" 2>/dev/null; then
    return 0
fi
- Impact:
1. The byte range \x80-\xFF matches all multibyte UTF-8 characters (international scripts, accented letters, emojis), incorrectly classifying valid UTF-8 text as binary.
2. `grep -P` (PCRE) is a GNU grep extension not available on standard BSD or macOS systems, causing binary detection to fail on those platforms.
- Remediation:
Detect binary data based on null bytes or non-printable ASCII characters without flagging UTF-8 high-bit bytes, and avoid using `grep -P`.
