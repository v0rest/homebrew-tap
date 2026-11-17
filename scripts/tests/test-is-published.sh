#!/usr/bin/env bash
# Tests for scripts/is-published.sh on formulae written by scripts/update-formula.sh, in a temp directory.
# Usage: scripts/tests/test-is-published.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../is-published.sh"
update="$here/../update-formula.sh"
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

sha="$(printf 'a%.0s' $(seq 64))"

# formula <version> - prints the path of a formula for that version, without a bottle block.
formula() {
    "$update" "$1" "$sha" "$tmp/$1/busysign.rb" > /dev/null
    echo "$tmp/$1/busysign.rb"
}

# bottled <version> - prints the path of a formula for that version with a bottle block after license.
bottled() {
    mkdir -p "$tmp/bottled-$1"
    awk '{ print } /^  license / { print ""; print "  bottle do"
        print "    root_url \"https://github.com/v0rest/homebrew-tap/releases/download/busysign-" v "\""
        print "    sha256 cellar: :any_skip_relocation, arm64_sequoia: \"" sha "\""; print "  end" }' \
        v="$1" sha="$sha" "$(formula "$1")" > "$tmp/bottled-$1/busysign.rb"
    echo "$tmp/bottled-$1/busysign.rb"
}

# expect <name> <formula> <version> <exit>
expect() {
    run "$script" "$2" "$3"
    if [[ $rc -ne $4 ]]; then
        fail "$1" "exit $rc, expected $4: $err"
    elif [[ $4 -eq 0 && $out != *"already has busysign $3" ]]; then
        fail "$1" "printed '$out'"
    elif [[ $4 -eq 1 && $out != *"does not have busysign $3" ]]; then
        fail "$1" "printed '$out'"
    else
        ok "$1"
    fi
}

expect "formula of this version is published" "$(formula 1.2.3)" 1.2.3 0
expect "bottled formula of this version is published" "$(bottled 1.2.3)" 1.2.3 0
expect "formula of an older version is not" "$(formula 1.2.2)" 1.2.3 1
expect "bottled formula of an older version is not" "$(bottled 1.2.2)" 1.2.3 1
expect "formula of a newer version is not" "$(formula 1.2.4)" 1.2.3 1
expect "1.2.30 is not 1.2.3" "$(formula 1.2.30)" 1.2.3 1
expect "no formula is not" "$tmp/none/busysign.rb" 1.2.3 1

name="the version only in the bottle block is not"
mkdir -p "$tmp/block-only"
sed 's|busysign-1.2.2"|busysign-1.2.3"|' "$(bottled 1.2.2)" > "$tmp/block-only/busysign.rb"
grep -q 'busysign-1.2.3"' "$tmp/block-only/busysign.rb" || { echo "FAIL $name: test setup"; exit 1; }
expect "$name" "$tmp/block-only/busysign.rb" 1.2.3 1

expect "malformed version exits 2" "$(formula 1.2.3)" v1.2.3 2
run "$script" "$(formula 1.2.3)"
if [[ $rc -ne 2 ]]; then fail "missing version exits 2" "exit $rc"; else ok "missing version exits 2"; fi

[[ $failures -eq 0 ]]
