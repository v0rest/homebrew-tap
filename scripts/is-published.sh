#!/usr/bin/env bash
# Exit 0 when the formula already has the busysign release url of this version, 1 when not (or no formula).
# Usage: scripts/is-published.sh <formula-path> <version>
set -euo pipefail

usage() {
    echo "usage: $0 <formula-path> <version>" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
formula="$1"
version="$2"
version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
if ! [[ $version =~ $version_re ]]; then
    echo "error: the version must look like 1.2.3" >&2
    exit 2
fi

url="https://github.com/v0rest/busysign/releases/download/v$version/busysign-$version.tar.gz"
if [[ -f $formula ]] && grep -qxF "  url \"$url\"" "$formula"; then
    echo "$formula already has busysign $version"
    exit 0
fi
echo "$formula does not have busysign $version"
exit 1
