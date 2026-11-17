#!/usr/bin/env bash
# Exit 1 when the formula's url already has a newer busysign version than the given one; a missing formula passes.
# Usage: scripts/check-not-older.sh <formula-path> <version>
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
if [[ ! -e $formula ]]; then
    echo "no formula at $formula yet"
    exit 0
fi

# Exactly one top-level url line, in the form scripts/update-formula.sh writes, with the same version twice.
num='([0-9]+\.[0-9]+\.[0-9]+)'
url_re='^  url "https://github\.com/v0rest/busysign/releases/download/v'"$num"'/busysign-'"$num"'\.tar\.gz"$'
current=""
urls=0
while IFS= read -r line || [[ -n $line ]]; do
    case $line in
        '  url '*)
            urls=$((urls + 1))
            if [[ $line =~ $url_re ]]; then
                if [[ ${BASH_REMATCH[1]} == "${BASH_REMATCH[2]}" ]]; then
                    current="${BASH_REMATCH[1]}"
                fi
            fi
            ;;
    esac
done < "$formula"
if [[ $urls -ne 1 || -z $current ]]; then
    echo "error: cannot read the version from the url in $formula" >&2
    exit 1
fi

# newer <a> <b> - true when X.Y.Z version a is newer than b, comparing each part as a decimal number.
newer() {
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<< "$1"
    IFS=. read -r b1 b2 b3 <<< "$2"
    if ((10#$a1 != 10#$b1)); then
        ((10#$a1 > 10#$b1))
        return
    fi
    if ((10#$a2 != 10#$b2)); then
        ((10#$a2 > 10#$b2))
        return
    fi
    ((10#$a3 > 10#$b3))
}

if newer "$current" "$version"; then
    echo "error: $formula is at $current, newer than $version; bump does not go back to an older version" >&2
    exit 1
fi
echo "$formula is at $current, the release is $version"
