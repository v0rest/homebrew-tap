#!/usr/bin/env bash
# Check a downloaded busysign release tarball against its .sha256 file; prints the verified sha256.
# Usage: scripts/verify-release.sh <dir> <version>
set -euo pipefail

usage() {
    echo "usage: $0 <dir> <version>" >&2
    exit 2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 2 ]] || usage
dir="$1"
version="$2"
version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
if ! [[ $version =~ $version_re ]]; then
    echo "error: the version must look like 1.2.3" >&2
    exit 2
fi

tarball="busysign-$version.tar.gz"
sumfile="$tarball.sha256"
[[ -f $dir/$tarball ]] || fail "$dir/$tarball is missing"
[[ -f $dir/$sumfile ]] || fail "$dir/$sumfile is missing"

# Exactly one line, "<sha>  <tarball>" as `shasum -a 256` writes it, naming this tarball and nothing else.
content="$(cat "$dir/$sumfile")"
case $content in
    *$'\n'*) fail "$sumfile has more than one line" ;;
esac
line_re='^([0-9a-f]{64})  (.+)$'
[[ $content =~ $line_re ]] || fail "$sumfile is not in 'shasum -a 256' format"
sha="${BASH_REMATCH[1]}"
named="${BASH_REMATCH[2]}"
[[ $named == "$tarball" ]] || fail "$sumfile names '$named', not $tarball"

if ! (cd "$dir" && shasum -a 256 -c "$sumfile") >&2; then
    fail "$tarball does not match $sumfile"
fi
echo "$sha"
