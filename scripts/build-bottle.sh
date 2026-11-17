#!/usr/bin/env bash
# Build a busysign bottle from the installed tap formula, pour it on this machine and check it; CI runners only.
# Usage: scripts/build-bottle.sh <version> <empty-output-dir>
set -euo pipefail

usage() {
    echo "usage: $0 <version> <empty-output-dir>" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
version="$1"
outdir="$2"
version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ $version =~ $version_re ]] || usage
if [[ -d $outdir && -n "$(ls -A "$outdir")" ]]; then
    echo "error: $outdir is not empty" >&2
    exit 2
fi
# It uninstalls and installs in the machine's Homebrew, which on a workstation may hold BusySign from another tap.
if [[ ${GITHUB_ACTIONS:-} != true ]]; then
    echo "error: $0 runs on GitHub Actions runners only" >&2
    exit 2
fi

mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"
root_url="https://github.com/v0rest/homebrew-tap/releases/download/busysign-$version"

# Homebrew before 7.0.13 loads `brew install` arguments through Formulary.factory, whose bottle loader refuses file
# paths unless HOMEBREW_DEVELOPER is set (FromBottleLoader.try_new, EnvConfig.forbid_packages_from_paths?); the failed
# load then shows as "Invalid tap name: '/users'". 7.0.13 and later pour a bottle path through Formulary.from_bottle,
# which has no such gate, so only older versions get HOMEBREW_DEVELOPER, and only for the pour.
brew_version="$(brew --version | sed -n '1s/^Homebrew \([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2 \3/p')"
[[ -n $brew_version ]] || { echo "error: cannot read the Homebrew version from brew --version" >&2; exit 1; }
read -r major minor patch <<< "$brew_version"
pour_env=()
if ((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch < 7000013)); then
    pour_env=(HOMEBREW_DEVELOPER=1)
fi

# brew uninstall drops a formula's trust unless its tap is trusted, and the bottle installed by path below is not a
# full name that brew install trusts again; without trust, brew info --installed leaves busysign out.
brew trust --tap v0rest/tap
# --build-bottle builds from source (it conflicts with --build-from-source); --no-rebuild keeps the file names
# free of a rebuild number, which brew bottle would otherwise look up in the tap's git history.
brew uninstall v0rest/tap/busysign
brew install --build-bottle v0rest/tap/busysign
(cd "$outdir" && brew bottle --json --no-rebuild --root-url="$root_url" v0rest/tap/busysign)

json="$(find "$outdir" -maxdepth 1 -name '*.bottle.json')"
[[ -n $json && $(printf '%s\n' "$json" | wc -l) -eq 1 ]] || { echo "error: expected one bottle JSON" >&2; exit 1; }
local_name="$(jq -r '.[].bottle.tags[].local_filename' "$json")"
[[ -f $outdir/$local_name ]] || { echo "error: brew bottle wrote no $local_name" >&2; exit 1; }

# Pour the bottle just built, the way a user's install would, and check the result.
brew uninstall v0rest/tap/busysign
env ${pour_env[@]+"${pour_env[@]}"} brew install "$outdir/$local_name"
"$(dirname "$0")/check-poured.sh" "$version"
