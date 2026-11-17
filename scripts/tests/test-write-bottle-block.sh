#!/usr/bin/env bash
# Tests for scripts/write-bottle-block.sh; the expected blocks are what `brew bottle --merge --write` wrote.
# Usage: scripts/tests/test-write-bottle-block.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../write-bottle-block.sh"
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

src_sha="$(printf 'c%.0s' $(seq 64))"
root="https://github.com/v0rest/homebrew-tap/releases/download/busysign"

# The sha256 values of the golden cases, as given to `brew bottle --merge`.
three_seq=eb15425aadb738df883762effef19fe3c7e5e5a014d5f70d64a1c79426ba4cb9
three_gg=ab22d638646cd95f42f985451e33d6a787d58d418b32ebf9aafdf3cccddd1cf4
three_tahoe=a1ba4bd84cf57a24a293477af86b3dc0b12eefdcd8bc8f8a0f5828b5d5a47e9a
mx_seq=2bf9ce783f01bc197b1a856aac09f7c39592b2711b3b1b1fc1e1c2b2e13910e2
mx_tahoe=7f4af95e70c0301c1bd1c583b4754f0771c883568664777d6b411edfa232b5e1
mx_gg=8e504f255032f8cc5db7a20678e49cd36df604ed4c189171109b8701c34739c4
one_seq=b844f6c9932a4046116c2adb298db78d9de39dacb1bdf94762735222d8e86e91
rb_seq=0566cc0d35748db9fd72519409e1c11295c0dfd176e02226b5968cbbe176d9ec
rb_tahoe=b073733c2377a940b237e543c0529ce7416471bbbb0af4584f7e07afc989bc74
cc_seq=53edc219f14c1225452b52f8b5bcbc64a86959fb683e04c4ec378b2e49ec62a0
cc_tahoe=408d734365f03e4b2e88626fa65887777ac9ab06b14ae120b88fd3deaadd3d4e

# bottle_json <out> <version> <tag> <cellar> <rebuild> <sha> [filename] [name]
# A file in the shape `brew bottle --json` writes (Homebrew dev-cmd/bottle.rb), one tag per file.
bottle_json() {
    local s=""
    [[ $5 -gt 0 ]] && s=".$5"
    jq -n --arg v "$2" --arg tag "$3" --arg cellar "$4" --argjson rebuild "$5" --arg sha "$6" --arg s "$s" \
        --arg filename "${7:-}" --arg name "${8:-busysign}" --arg root "$root" '
        {("v0rest/tap/" + $name): {
          "formula": {"name": $name, "pkg_version": $v, "path": "Library/Taps/v0rest/homebrew-tap/Formula/busysign.rb",
                      "tap_git_path": "Formula/busysign.rb", "tap_git_revision": null, "tap_git_remote": null,
                      "desc": "Menu-bar app", "license": "MIT", "homepage": "https://github.com/v0rest/busysign"},
          "bottle": {"root_url": ($root + "-" + $v), "cellar": $cellar, "rebuild": $rebuild,
                     "date": "2026-11-17T12:00:00Z",
                     "tags": {($tag): {
                       "filename": (if $filename == "" then "busysign-" + $v + "." + $tag + ".bottle" + $s + ".tar.gz"
                                    else $filename end),
                       "local_filename": ("busysign--" + $v + "." + $tag + ".bottle" + $s + ".tar.gz"),
                       "sha256": $sha, "tab": {}, "binary_relocation_diagnostics": [], "sbom": {},
                       "path_exec_files": [], "all_files": [], "installed_size": 1}}}}}' > "$1"
}

# case_dir <name> <version> - a directory with a fresh formula from update-formula.sh; prints its path.
case_dir() {
    mkdir -p "$tmp/$1"
    "$update" "$2" "$src_sha" "$tmp/$1/busysign.rb" > /dev/null
    cp "$tmp/$1/busysign.rb" "$tmp/$1/before.rb"
    echo "$tmp/$1"
}

# expect_block <name> <dir> <block file> - the formula is before.rb with the block after license's blank line.
expect_block() {
    { head -n 7 "$2/before.rb"; cat "$3"; echo; tail -n +8 "$2/before.rb"; } > "$2/expected.rb"
    if [[ $rc -ne 0 ]]; then
        fail "$1" "exit $rc: $err"
    elif ! cmp -s "$2/expected.rb" "$2/busysign.rb"; then
        fail "$1" "$(diff "$2/expected.rb" "$2/busysign.rb" | head -20)"
    elif [[ $out != "bottle block for "*" written to $2/busysign.rb" ]]; then
        fail "$1" "printed '$out'"
    else
        ok "$1"
    fi
}

# Three runners, any_skip_relocation, files given out of order.
d="$(case_dir three 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any_skip_relocation 0 "$three_seq"
bottle_json "$d/b.json" 0.1.0 arm64_golden_gate any_skip_relocation 0 "$three_gg"
bottle_json "$d/c.json" 0.1.0 arm64_tahoe any_skip_relocation 0 "$three_tahoe"
cat > "$d/block" <<EOF
  bottle do
    root_url "https://github.com/v0rest/homebrew-tap/releases/download/busysign-0.1.0"
    sha256 cellar: :any_skip_relocation, arm64_golden_gate: "${three_gg}"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:       "${three_tahoe}"
    sha256 cellar: :any_skip_relocation, arm64_sequoia:     "${three_seq}"
  end
EOF
run "$script" "$d/busysign.rb" "$d/a.json" "$d/b.json" "$d/c.json"
expect_block "three tags, newest macOS first" "$d" "$d/block"

# Mixed cellars: a default cellar gets no cellar: argument, the columns still line up.
d="$(case_dir mixed 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia /opt/homebrew/Cellar 0 "$mx_seq"
bottle_json "$d/b.json" 0.1.0 arm64_tahoe any 0 "$mx_tahoe"
bottle_json "$d/c.json" 0.1.0 arm64_golden_gate any_skip_relocation 0 "$mx_gg"
cat > "$d/block" <<EOF
  bottle do
    root_url "https://github.com/v0rest/homebrew-tap/releases/download/busysign-0.1.0"
    sha256 cellar: :any_skip_relocation, arm64_golden_gate: "${mx_gg}"
    sha256 cellar: :any,                 arm64_tahoe:       "${mx_tahoe}"
    sha256                               arm64_sequoia:     "${mx_seq}"
  end
EOF
run "$script" "$d/busysign.rb" "$d/a.json" "$d/b.json" "$d/c.json"
expect_block "mixed cellars line up" "$d" "$d/block"

d="$(case_dir single 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$one_seq"
cat > "$d/block" <<EOF
  bottle do
    root_url "https://github.com/v0rest/homebrew-tap/releases/download/busysign-0.1.0"
    sha256 cellar: :any, arm64_sequoia: "${one_seq}"
  end
EOF
run "$script" "$d/busysign.rb" "$d/a.json"
expect_block "single tag" "$d" "$d/block"

d="$(case_dir rebuild 1.2.3)"
bottle_json "$d/a.json" 1.2.3 arm64_sequoia any_skip_relocation 1 "$rb_seq"
bottle_json "$d/b.json" 1.2.3 arm64_tahoe any_skip_relocation 1 "$rb_tahoe"
cat > "$d/block" <<EOF
  bottle do
    root_url "https://github.com/v0rest/homebrew-tap/releases/download/busysign-1.2.3"
    rebuild 1
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "${rb_tahoe}"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "${rb_seq}"
  end
EOF
run "$script" "$d/busysign.rb" "$d/a.json" "$d/b.json"
expect_block "rebuild line" "$d" "$d/block"

d="$(case_dir custom-cellar 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia /opt/custom/Cellar 0 "$cc_seq"
bottle_json "$d/b.json" 0.1.0 arm64_tahoe /opt/homebrew/Cellar 0 "$cc_tahoe"
cat > "$d/block" <<EOF
  bottle do
    root_url "https://github.com/v0rest/homebrew-tap/releases/download/busysign-0.1.0"
    sha256                               arm64_tahoe:   "${cc_tahoe}"
    sha256 cellar: "/opt/custom/Cellar", arm64_sequoia: "${cc_seq}"
  end
EOF
run "$script" "$d/busysign.rb" "$d/a.json" "$d/b.json"
expect_block "custom cellar path" "$d" "$d/block"

# expect_refused <name> <dir> <text in stderr> <json...> - exit 1 and the formula untouched.
expect_refused() {
    local name="$1" dir="$2" text="$3"
    shift 3
    run "$script" "$dir/busysign.rb" "$@"
    if [[ $rc -ne 1 ]]; then
        fail "$name" "exit $rc, expected 1: $err"
    elif [[ $err != *"$text"* ]]; then
        fail "$name" "stderr lacks '$text': $err"
    elif ! cmp -s "$dir/before.rb" "$dir/busysign.rb"; then
        fail "$name" "formula changed"
    else
        ok "$name"
    fi
}

sha1="$(printf '1%.0s' $(seq 64))"
sha2="$(printf '2%.0s' $(seq 64))"

d="$(case_dir identical 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any_skip_relocation 0 "$sha1"
bottle_json "$d/b.json" 0.1.0 arm64_tahoe any_skip_relocation 0 "$sha1"
expect_refused "identical bottles (an all: bottle) refused" "$d" "all:" "$d/a.json" "$d/b.json"

d="$(case_dir local-name 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1" busysign--0.1.0.arm64_sequoia.bottle.tar.gz
expect_refused "local file name as the remote name refused" "$d" "remote file name" "$d/a.json"

d="$(case_dir other-version 0.1.0)"
bottle_json "$d/a.json" 0.1.1 arm64_sequoia any 0 "$sha1"
expect_refused "bottle of another version refused" "$d" "0.1.1" "$d/a.json"

d="$(case_dir same-tag 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1"
bottle_json "$d/b.json" 0.1.0 arm64_sequoia any 0 "$sha2"
expect_refused "two bottles for one tag refused" "$d" "arm64_sequoia" "$d/a.json" "$d/b.json"

d="$(case_dir unknown-tag 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_future any 0 "$sha1"
expect_refused "unknown tag refused" "$d" "arm64_future" "$d/a.json"

d="$(case_dir other-formula 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1" "" otherapp
expect_refused "bottle of another formula refused" "$d" "busysign" "$d/a.json"

d="$(case_dir bad-sha 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "${sha1:1}"
expect_refused "malformed sha256 refused" "$d" "sha256" "$d/a.json"

d="$(case_dir root-urls 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1"
bottle_json "$d/b.json" 0.1.0 arm64_tahoe any 0 "$sha2"
jq '.[].bottle.root_url = "https://example.com/elsewhere"' "$d/b.json" > "$d/b2.json"
expect_refused "different root urls refused" "$d" "root_url" "$d/a.json" "$d/b2.json"

# The root_url must be exactly this tap's release for the formula's version.
d="$(case_dir other-repo 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1"
jq '.[].bottle.root_url = "https://github.com/someone/homebrew-tap/releases/download/busysign-0.1.0"' \
    "$d/a.json" > "$d/a2.json"
expect_refused "root_url of another repository refused" "$d" "root_url" "$d/a2.json"

d="$(case_dir other-release 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1"
jq '.[].bottle.root_url = "https://github.com/v0rest/homebrew-tap/releases/download/busysign-0.1.1"' \
    "$d/a.json" > "$d/a2.json"
expect_refused "root_url of another release refused" "$d" "root_url" "$d/a2.json"

d="$(case_dir trailing-slash 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1"
jq '.[].bottle.root_url += "/"' "$d/a.json" > "$d/a2.json"
expect_refused "root_url with a trailing slash refused" "$d" "root_url" "$d/a2.json"

d="$(case_dir has-block 0.1.0)"
bottle_json "$d/a.json" 0.1.0 arm64_sequoia any 0 "$sha1"
run "$script" "$d/busysign.rb" "$d/a.json"
cp "$d/busysign.rb" "$d/before.rb"
expect_refused "formula that already has a bottle block refused" "$d" "bottle block" "$d/a.json"

run "$script" "$tmp/three/busysign.rb"
if [[ $rc -ne 2 ]]; then fail "no JSON exits 2" "exit $rc"; else ok "no JSON exits 2"; fi
run "$script" "$tmp/nope.rb" "$tmp/three/a.json"
if [[ $rc -ne 2 ]]; then fail "missing formula exits 2" "exit $rc"; else ok "missing formula exits 2"; fi

[[ $failures -eq 0 ]]
