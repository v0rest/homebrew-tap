#!/usr/bin/env bash
# Check that the installed busysign was poured from a bottle, carries no quarantine, verifies and runs.
# Usage: scripts/check-poured.sh <version>
set -euo pipefail

usage() {
    echo "usage: $0 <version>" >&2
    exit 2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || usage
version="$1"
version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
if ! [[ $version =~ $version_re ]]; then
    echo "error: the version must look like 1.2.3" >&2
    exit 2
fi

# Exactly one installed busysign keg, of this version, poured from a bottle.
info="$(brew info --json=v2 --installed)"
installed="$(jq -c '[.formulae[] | select(.name == "busysign") | .installed[]]' <<< "$info")"
count="$(jq 'length' <<< "$installed")"
[[ $count -eq 1 ]] || fail "expected one installed busysign, found $count"
keg_version="$(jq -r '.[0].version' <<< "$installed")"
[[ $keg_version == "$version" ]] || fail "busysign $keg_version is installed, not $version"
poured="$(jq -r '.[0].poured_from_bottle' <<< "$installed")"
[[ $poured == true ]] || fail "busysign $version was not poured from a bottle (poured_from_bottle: $poured)"

app="$(brew --prefix v0rest/tap/busysign)/BusySign.app"
[[ -d $app ]] || fail "no $app"
attrs="$(xattr -r "$app")"
case $attrs in
    *com.apple.quarantine*) fail "com.apple.quarantine is set in $app: $(grep com.apple.quarantine <<< "$attrs")" ;;
esac
codesign --verify --deep --strict "$app" || fail "codesign --verify --deep --strict failed for $app"
printed="$("$app/Contents/MacOS/BusySign" --version)"
[[ $printed == "$version" ]] || fail "BusySign --version printed '$printed', not $version"
echo "busysign $version: poured from a bottle, no quarantine, signature verifies, --version matches"
