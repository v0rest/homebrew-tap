#!/usr/bin/env bash
# Tests for scripts/check-not-older.sh on formulae written by scripts/update-formula.sh, in a temp directory.
# Usage: scripts/tests/test-check-not-older.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../check-not-older.sh"
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

# formula <version> - prints the path of a formula for that version.
formula() {
    "$update" "$1" "$sha" "$tmp/$1/busysign.rb" > /dev/null
    echo "$tmp/$1/busysign.rb"
}

# expect <name> <formula> <version> <exit> [text in stderr]
expect() {
    run "$script" "$2" "$3"
    if [[ $rc -ne $4 ]]; then
        fail "$1" "exit $rc, expected $4: $err"
    elif [[ -n ${5:-} && $err != *"$5"* ]]; then
        fail "$1" "stderr lacks '$5': $err"
    elif [[ $4 -ne 0 && -n $out ]]; then
        fail "$1" "printed '$out' on stdout"
    else
        ok "$1"
    fi
}

expect "older formula passes" "$(formula 1.2.3)" 1.2.4 0
expect "equal version passes" "$(formula 1.2.3)" 1.2.3 0
expect "newer formula fails" "$(formula 1.2.4)" 1.2.3 1 "1.2.4, newer than 1.2.3"
expect "1.10.0 is newer than 1.9.0" "$(formula 1.10.0)" 1.9.0 1 "1.10.0, newer than 1.9.0"
expect "1.9.0 is older than 1.10.0" "$(formula 1.9.0)" 1.10.0 0
expect "2.0.0 is newer than 1.99.99" "$(formula 2.0.0)" 1.99.99 1
expect "1.3.0 is newer than 1.2.99" "$(formula 1.3.0)" 1.2.99 1
expect "leading zeros compare as decimal" "$(formula 1.09.0)" 1.10.0 0
expect "1.09.0 is newer than 1.8.0" "$(formula 1.09.0)" 1.8.0 1 "1.09.0, newer than 1.8.0"
expect "no formula passes" "$tmp/none/busysign.rb" 1.2.3 0

name="unreadable url fails"
mkdir -p "$tmp/archive"
sed 's|releases/download/v1.2.3/busysign-1.2.3.tar.gz|archive/refs/tags/v1.2.3.tar.gz|' \
    "$(formula 1.2.3)" > "$tmp/archive/busysign.rb"
expect "$name" "$tmp/archive/busysign.rb" 1.2.3 1 "cannot read the version"

name="url with two different versions fails"
mkdir -p "$tmp/mixed"
sed 's|/busysign-1.2.3.tar.gz|/busysign-1.2.4.tar.gz|' "$(formula 1.2.3)" > "$tmp/mixed/busysign.rb"
expect "$name" "$tmp/mixed/busysign.rb" 1.2.3 1 "cannot read the version"

expect "malformed version exits 2" "$(formula 1.2.3)" v1.2.3 2
run "$script" "$(formula 1.2.3)"
if [[ $rc -ne 2 ]]; then fail "missing version exits 2" "exit $rc"; else ok "missing version exits 2"; fi

[[ $failures -eq 0 ]]
