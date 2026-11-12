#!/bin/sh
#
# The config runs on macOS too, whose sed is BSD's. These check the sed calls
# for the GNU-only forms that BSD sed rejects or reads differently.

. "$(dirname "$0")/shrc_test_lib.sh"

_files="shrc shrc.vcs profile exitrc config/fish/config.fish
config/mesh/rc.mesh config/elvish/rc.elv config/nushell/config.nu
config/kitty/tide-bell"

# The lines of the files above that run sed, as "file:line: text".
_sed_lines=$(cd "$_srcdir" && grep -nE '(^|[^a-zA-Z_.-])\^?sed[[:space:]]' $_files /dev/null |
    grep -vE '^[^:]*:[0-9]*:[[:space:]]*#')

start_test "the sed check sees the config's sed calls"
assert_contains "shrc:" "$_sed_lines"
assert_contains "config/nushell/config.nu:" "$_sed_lines"

# BSD sed wants a `;` (or a newline) before a closing brace: `{p}` is
# "extra characters at the end of p command".
start_test "every sed block ends its last command with a semicolon"
assert_equal "" "$(printf '%s\n' "$_sed_lines" | grep -E "'[^']*[^;{[:space:]^]}[^']*'")"

# BSD sed's -i takes the next argument as the backup suffix, so `-i -e` makes
# a backup named "<file>-e". A suffix attached to -i is read the same by both.
start_test "every sed -i has its backup suffix attached"
assert_equal "" "$(printf '%s\n' "$_sed_lines" | grep -E 'sed[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*i([[:space:]]|$)')"

# -r is GNU's spelling; -E is the one both seds take.
start_test "sed takes -E, not -r, for extended regular expressions"
assert_equal "" "$(printf '%s\n' "$_sed_lines" | grep -E 'sed[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*r')"

test_summary "portable-sed"
