#!/usr/bin/env bash
# Install, test and audit a busysign formula from source as v0rest/tap/busysign; GitHub Actions runners only.
# Usage: scripts/test-formula.sh <formula-path>
set -euo pipefail

usage() {
    echo "usage: $0 <formula-path>" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
formula="$1"
[[ -f $formula ]] || { echo "error: no formula at $formula" >&2; exit 2; }
# It installs into the machine's Homebrew, which on a workstation may already have BusySign from another tap.
if [[ ${GITHUB_ACTIONS:-} != true ]]; then
    echo "error: $0 runs on GitHub Actions runners only" >&2
    exit 2
fi

swift --version
tap_dir="$(brew --repository)/Library/Taps/v0rest/homebrew-tap"
mkdir -p "$tap_dir/Formula"
cp "$formula" "$tap_dir/Formula/busysign.rb"
brew install --build-from-source v0rest/tap/busysign
brew test v0rest/tap/busysign
brew audit --strict --formula v0rest/tap/busysign
