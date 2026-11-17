#!/usr/bin/env bash
# Write the busysign formula for a release; prints "updated", or "unchanged" when the file is already byte-identical.
# Usage: scripts/update-formula.sh <version> <sha256> [formula-path (default: Formula/busysign.rb)]
set -euo pipefail

usage() {
    echo "usage: $0 <version> <sha256> [formula-path]" >&2
    exit 2
}

[[ $# -eq 2 || $# -eq 3 ]] || usage
version="$1"
sha="$2"
version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
sha_re='^[0-9a-f]{64}$'
if ! [[ $version =~ $version_re ]]; then
    echo "error: the version must look like 1.2.3" >&2
    exit 2
fi
if ! [[ $sha =~ $sha_re ]]; then
    echo "error: the sha256 must be 64 lowercase hex characters" >&2
    exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
formula="${3:-$root/Formula/busysign.rb}"

# The whole formula comes from here, so a change to Formula/busysign.rb belongs in this template.
render() {
    cat <<EOF
class Busysign < Formula
  desc "Menu-bar app that mirrors plain Busy blocks between your macOS calendars"
  homepage "https://github.com/v0rest/busysign"
  url "https://github.com/v0rest/busysign/releases/download/v${version}/busysign-${version}.tar.gz"
  sha256 "${sha}"
  license "MIT"

  depends_on macos: :sequoia

EOF
    cat <<'EOF'
  def install
    system "scripts/build-app.sh", "--disable-sandbox", "--output", "#{buildpath}/BusySign.app"
    prefix.install "BusySign.app"
  end

  def caveats
    <<~EOS
      BusySign is not running yet. Open it once and allow calendar access when macOS asks:
        open #{opt_prefix}/BusySign.app

      Do this again after every upgrade. Quit the old BusySign from its menu-bar icon first.
      Each build is signed ad hoc, so macOS treats the new build as a new app and asks
      for calendar access again.
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{prefix}/BusySign.app/Contents/MacOS/BusySign --version").strip
  end
end
EOF
}

mkdir -p "$(dirname "$formula")"
tmp="$(mktemp "$formula.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
render > "$tmp"
if [[ -f $formula ]] && cmp -s "$tmp" "$formula"; then
    echo unchanged
    exit 0
fi
chmod 644 "$tmp"
mv "$tmp" "$formula"
echo updated
