#!/usr/bin/env bash
# Tests for scripts/verify-release.sh, run in a temp directory.
# Usage: scripts/tests/test-verify-release.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../verify-release.sh"
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

# release <dir> - a tarball for 1.2.3 and its .sha256 in the format the busysign release publishes.
release() {
    mkdir -p "$1/src/busysign-1.2.3"
    printf '1.2.3\n' > "$1/src/busysign-1.2.3/VERSION"
    tar -czf "$1/busysign-1.2.3.tar.gz" -C "$1/src" busysign-1.2.3
    rm -rf "$1/src"
    (cd "$1" && shasum -a 256 busysign-1.2.3.tar.gz > busysign-1.2.3.tar.gz.sha256)
}

name="good pair passes and prints the sha"
dir="$tmp/good"
release "$dir"
expected="$(cut -d' ' -f1 "$dir/busysign-1.2.3.tar.gz.sha256")"
run "$script" "$dir" 1.2.3
if [[ $rc -ne 0 ]]; then
    fail "$name" "exit $rc: $err"
elif [[ $out != "$expected" ]]; then
    fail "$name" "printed '$out', expected '$expected'"
else
    ok "$name"
fi

name="one byte changed in the tarball fails"
dir="$tmp/tampered"
release "$dir"
size="$(wc -c < "$dir/busysign-1.2.3.tar.gz" | tr -d ' ')"
offset=$((size / 2))
# Write a byte that differs from the one already there.
byte="$(od -An -tu1 -j "$offset" -N 1 "$dir/busysign-1.2.3.tar.gz" | tr -d ' \n')"
replacement=X
[[ $byte == 88 ]] && replacement=Y
cp "$dir/busysign-1.2.3.tar.gz" "$tmp/original.tar.gz"
printf '%s' "$replacement" | dd of="$dir/busysign-1.2.3.tar.gz" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null
run "$script" "$dir" 1.2.3
if cmp -s "$tmp/original.tar.gz" "$dir/busysign-1.2.3.tar.gz"; then
    fail "$name" "the tarball was not changed"
elif [[ $rc -ne 1 ]]; then
    fail "$name" "exit $rc, expected 1"
elif [[ -n $out ]]; then
    fail "$name" "printed '$out' on stdout"
elif [[ $err != *"does not match"* ]]; then
    fail "$name" "wrong reason: $err"
else
    ok "$name"
fi

# The .sha256 names another file that exists and matches its own hash.
name=".sha256 naming another file fails"
dir="$tmp/other"
release "$dir"
cp "$dir/busysign-1.2.3.tar.gz" "$dir/other.tar.gz"
(cd "$dir" && shasum -a 256 other.tar.gz > busysign-1.2.3.tar.gz.sha256)
run "$script" "$dir" 1.2.3
if [[ $rc -ne 1 ]]; then
    fail "$name" "exit $rc, expected 1"
elif [[ $err != *"names 'other.tar.gz'"* ]]; then
    fail "$name" "wrong reason: $err"
else
    ok "$name"
fi

name=".sha256 with a second line fails"
dir="$tmp/two-lines"
release "$dir"
cp "$dir/busysign-1.2.3.tar.gz" "$dir/other.tar.gz"
(cd "$dir" && shasum -a 256 other.tar.gz >> busysign-1.2.3.tar.gz.sha256)
run "$script" "$dir" 1.2.3
if [[ $rc -ne 1 ]]; then
    fail "$name" "exit $rc, expected 1"
elif [[ $err != *"more than one line"* ]]; then
    fail "$name" "wrong reason: $err"
else
    ok "$name"
fi

name="missing .sha256 fails"
dir="$tmp/no-sum"
release "$dir"
rm "$dir/busysign-1.2.3.tar.gz.sha256"
run "$script" "$dir" 1.2.3
if [[ $rc -ne 1 ]]; then
    fail "$name" "exit $rc, expected 1"
else
    ok "$name"
fi

name="missing tarball fails"
dir="$tmp/no-tarball"
release "$dir"
rm "$dir/busysign-1.2.3.tar.gz"
run "$script" "$dir" 1.2.3
if [[ $rc -ne 1 ]]; then
    fail "$name" "exit $rc, expected 1"
else
    ok "$name"
fi

name="other version fails"
run "$script" "$tmp/good" 1.2.4
if [[ $rc -ne 1 ]]; then
    fail "$name" "exit $rc, expected 1"
else
    ok "$name"
fi

name="malformed version exits 2"
run "$script" "$tmp/good" 1.2
if [[ $rc -ne 2 ]]; then
    fail "$name" "exit $rc, expected 2"
else
    ok "$name"
fi

name="missing argument exits 2"
run "$script" "$tmp/good"
if [[ $rc -ne 2 ]]; then
    fail "$name" "exit $rc, expected 2"
else
    ok "$name"
fi

[[ $failures -eq 0 ]]
