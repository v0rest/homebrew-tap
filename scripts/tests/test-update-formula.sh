#!/usr/bin/env bash
# Tests for scripts/update-formula.sh, run in a temp directory.
# Usage: scripts/tests/test-update-formula.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../update-formula.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
ok() { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; failures=$((failures + 1)); }

# run <command...> - sets $out (stdout), $err (stderr) and $rc without stopping on failure.
run() {
    set +e
    out="$("$@" 2>"$tmp/stderr")"
    rc=$?
    set -e
    err="$(cat "$tmp/stderr")"
}

sha_a="$(printf 'a%.0s' $(seq 64))"
sha_b="$(printf 'b%.0s' $(seq 64))"
url='https://github.com/v0rest/busysign/releases/download/v1.2.3/busysign-1.2.3.tar.gz'

# A new formula in a directory that does not exist yet.
name="writes a new formula"
formula="$tmp/new/Formula/busysign.rb"
run "$script" 1.2.3 "$sha_a" "$formula"
if [[ $rc -ne 0 ]]; then
    fail "$name" "exit $rc: $err"
elif [[ $out != updated ]]; then
    fail "$name" "printed '$out', expected 'updated'"
elif [[ ! -f $formula ]]; then
    fail "$name" "no file at $formula"
elif ! grep -qxF "  url \"$url\"" "$formula"; then
    fail "$name" "url line missing"
elif ! grep -qxF "  sha256 \"$sha_a\"" "$formula"; then
    fail "$name" "sha256 line missing"
elif grep -qE '^[[:space:]]*version[[:space:]]' "$formula"; then
    fail "$name" "has a version line"
else
    ok "$name"
fi

name="keeps the install, caveats and test blocks"
missing=""
for line in \
    'class Busysign < Formula' \
    '  license "MIT"' \
    '  depends_on macos: :sequoia' \
    '    system "scripts/build-app.sh", "--disable-sandbox", "--output", "#{buildpath}/BusySign.app"' \
    '    prefix.install "BusySign.app"' \
    '        open #{opt_prefix}/BusySign.app' \
    '  test do' \
    '    assert_equal version.to_s, shell_output("#{prefix}/BusySign.app/Contents/MacOS/BusySign --version").strip'
do
    grep -qxF "$line" "$formula" || missing="$missing [$line]"
done
if [[ -n $missing ]]; then
    fail "$name" "lines missing:$missing"
elif grep -q PLACEHOLDER "$formula"; then
    fail "$name" "still has the PLACEHOLDER comment"
else
    ok "$name"
fi

# The same version and sha again: nothing changes.
name="second run is unchanged"
cp "$formula" "$tmp/before.rb"
run "$script" 1.2.3 "$sha_a" "$formula"
if [[ $rc -ne 0 ]]; then
    fail "$name" "exit $rc: $err"
elif [[ $out != unchanged ]]; then
    fail "$name" "printed '$out', expected 'unchanged'"
elif ! cmp -s "$tmp/before.rb" "$formula"; then
    fail "$name" "file changed"
elif [[ -n "$(find "$(dirname "$formula")" -type f ! -name busysign.rb)" ]]; then
    fail "$name" "left other files next to the formula"
else
    ok "$name"
fi

# Another sha for the same version: the file is rewritten.
name="new sha is updated"
run "$script" 1.2.3 "$sha_b" "$formula"
if [[ $rc -ne 0 || $out != updated ]]; then
    fail "$name" "exit $rc, printed '$out': $err"
elif ! grep -qxF "  sha256 \"$sha_b\"" "$formula" || grep -qF "$sha_a" "$formula"; then
    fail "$name" "sha256 not replaced"
else
    ok "$name"
fi

# add_bottle_block <formula> - a bottle block where `brew bottle --merge` puts it, after license and a blank line.
add_bottle_block() {
    awk '
        { print }
        /^  license / { license = 1; next }
        license && /^$/ {
            print "  bottle do"
            print "    root_url \"https://github.com/v0rest/homebrew-tap/releases/download/busysign-1.2.3\""
            print "    sha256 cellar: :any_skip_relocation, arm64_sequoia: \"" sha "\""
            print "  end"
            print ""
            license = 0
        }
    ' sha="$sha_a" "$1" > "$1.tmp"
    mv "$1.tmp" "$1"
}

# The source decides: a matching url and sha256 is unchanged, with or without a bottle block.
name="bottle block with the same url and sha is unchanged"
add_bottle_block "$formula"
cp "$formula" "$tmp/with-bottle.rb"
grep -qx '  bottle do' "$formula" || { echo "FAIL $name: test setup added no bottle block"; exit 1; }
run "$script" 1.2.3 "$sha_b" "$formula"
if [[ $rc -ne 0 || $out != unchanged ]]; then
    fail "$name" "exit $rc, printed '$out': $err"
elif ! cmp -s "$tmp/with-bottle.rb" "$formula"; then
    fail "$name" "file changed"
else
    ok "$name"
fi

name="hand edit with the same url and sha is unchanged"
printf '# hand edit\n' >> "$formula"
cp "$formula" "$tmp/hand-edit.rb"
run "$script" 1.2.3 "$sha_b" "$formula"
if [[ $rc -ne 0 || $out != unchanged ]]; then
    fail "$name" "exit $rc, printed '$out': $err"
elif ! cmp -s "$tmp/hand-edit.rb" "$formula"; then
    fail "$name" "file changed"
else
    ok "$name"
fi

name="new sha drops the bottle block"
run "$script" 1.2.3 "$sha_a" "$formula"
if [[ $rc -ne 0 || $out != updated ]]; then
    fail "$name" "exit $rc, printed '$out': $err"
elif grep -q 'bottle do\|hand edit' "$formula"; then
    fail "$name" "bottle block or hand edit kept"
elif ! grep -qxF "  sha256 \"$sha_a\"" "$formula"; then
    fail "$name" "sha256 not replaced"
else
    ok "$name"
fi

name="new version drops the bottle block"
add_bottle_block "$formula"
run "$script" 1.2.4 "$sha_a" "$formula"
if [[ $rc -ne 0 || $out != updated ]]; then
    fail "$name" "exit $rc, printed '$out': $err"
elif grep -q 'bottle do' "$formula"; then
    fail "$name" "bottle block kept"
elif ! grep -qF 'releases/download/v1.2.4/busysign-1.2.4.tar.gz"' "$formula"; then
    fail "$name" "url not replaced"
else
    ok "$name"
fi

# Malformed arguments exit 2 and leave the file alone.
cp "$formula" "$tmp/before.rb"
check_rejected() {
    local name="$1"
    shift
    run "$script" "$@"
    if [[ $rc -ne 2 ]]; then
        fail "$name" "exit $rc, expected 2"
    elif ! cmp -s "$tmp/before.rb" "$formula"; then
        fail "$name" "file changed"
    else
        ok "$name"
    fi
}
check_rejected "version 1.2 exits 2" 1.2 "$sha_a" "$formula"
check_rejected "version v1.2.3 exits 2" v1.2.3 "$sha_a" "$formula"
check_rejected "63-char sha exits 2" 1.2.3 "${sha_a:1}" "$formula"
check_rejected "65-char sha exits 2" 1.2.3 "${sha_a}a" "$formula"
check_rejected "uppercase sha exits 2" 1.2.3 "$(printf 'A%.0s' $(seq 64))" "$formula"
check_rejected "missing sha exits 2" 1.2.3
check_rejected "extra argument exits 2" 1.2.3 "$sha_a" "$formula" extra

name="malformed version writes nothing"
run "$script" 1.2 "$sha_a" "$tmp/never/busysign.rb"
if [[ $rc -ne 2 ]]; then
    fail "$name" "exit $rc, expected 2"
elif [[ -e $tmp/never ]]; then
    fail "$name" "created $tmp/never"
else
    ok "$name"
fi

# Without a path it writes Formula/busysign.rb next to its own scripts/ directory.
name="default path is the repo's Formula/busysign.rb"
mkdir -p "$tmp/repo/scripts"
cp "$script" "$tmp/repo/scripts/update-formula.sh"
run "$tmp/repo/scripts/update-formula.sh" 1.2.3 "$sha_a"
if [[ $rc -ne 0 || $out != updated ]]; then
    fail "$name" "exit $rc, printed '$out': $err"
elif ! grep -qxF "  sha256 \"$sha_a\"" "$tmp/repo/Formula/busysign.rb"; then
    fail "$name" "no formula at $tmp/repo/Formula/busysign.rb"
else
    ok "$name"
fi

[[ $failures -eq 0 ]]
