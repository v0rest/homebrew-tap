#!/usr/bin/env bash
# Tests for scripts/upload-bottles.sh with a stub gh that keeps the release in a temp directory.
# Usage: scripts/tests/test-upload-bottles.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../upload-bottles.sh"
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

# Stub gh: the release is the directory $STUB_RELEASE; upload copies files there except $STUB_DROP;
# the asset listing reports $STUB_CORRUPT with a wrong digest.
stubs="$tmp/bin"
mkdir -p "$stubs"
cat > "$stubs/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_LOG"
case "$1 $2" in
    "release view")
        [[ -d $STUB_RELEASE ]] || { echo "release not found" >&2; exit 1; }
        if [[ "$*" == *"--json assets"* ]]; then
            assets='[]'
            for f in "$STUB_RELEASE"/*; do
                [[ -f $f ]] || continue
                name="$(basename "$f")"
                digest="sha256:$(shasum -a 256 "$f" | cut -d' ' -f1)"
                [[ $name == "${STUB_CORRUPT:-}" ]] && digest="sha256:$(printf '0%.0s' $(seq 64))"
                assets="$(jq --arg n "$name" --arg d "$digest" --argjson s "$(wc -c < "$f" | tr -d ' ')" \
                    '. + [{name: $n, size: $s, digest: $d, state: "uploaded"}]' <<< "$assets")"
            done
            jq -n --argjson a "$assets" '{assets: $a}'
        fi
        ;;
    "release create") mkdir -p "$STUB_RELEASE" ;;
    "release upload")
        [[ -d $STUB_RELEASE ]] || { echo "release not found" >&2; exit 1; }
        for arg in "$@"; do
            if [[ -f $arg && "$(basename "$arg")" != "${STUB_DROP:-}" ]]; then
                cp "$arg" "$STUB_RELEASE/"
            fi
        done
        ;;
    *) echo "stub gh: unexpected $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$stubs/gh"
PATH="$stubs:$PATH"
export PATH STUB_LOG STUB_RELEASE STUB_DROP STUB_CORRUPT
if [[ "$(command -v gh)" != "$stubs/gh" ]]; then
    echo "FAIL upload-bottles: stub gh is not first in PATH, not running"
    exit 1
fi

repo="v0rest/homebrew-tap"
tag="busysign-1.2.3"

# bottle <dir> <tag> - a fake bottle under its local name and the JSON `brew bottle --json` writes for it.
bottle() {
    local local_name="busysign--1.2.3.$2.bottle.tar.gz"
    printf 'bottle for %s\n' "$2" > "$1/$local_name"
    jq -n --arg tag "$2" --arg local "$local_name" --arg sha "$(shasum -a 256 "$1/$local_name" | cut -d' ' -f1)" \
        '{"v0rest/tap/busysign": {"formula": {"name": "busysign", "pkg_version": "1.2.3"},
          "bottle": {"root_url": "https://github.com/v0rest/homebrew-tap/releases/download/busysign-1.2.3",
                     "cellar": "any_skip_relocation", "rebuild": 0,
                     "tags": {($tag): {"filename": ("busysign-1.2.3." + $tag + ".bottle.tar.gz"),
                                       "local_filename": $local, "sha256": $sha}}}}}' \
        > "$1/busysign--1.2.3.$2.bottle.json"
}

# reset <name> - two bottles, no release yet, a fresh log.
reset() {
    dir="$tmp/$1/bottles"
    mkdir -p "$dir"
    bottle "$dir" arm64_sequoia
    bottle "$dir" arm64_tahoe
    STUB_RELEASE="$tmp/$1/release"
    STUB_LOG="$tmp/$1/gh.log"
    STUB_DROP=""
    STUB_CORRUPT=""
    : > "$STUB_LOG"
}

remote_names="busysign-1.2.3.arm64_sequoia.bottle.tar.gz
busysign-1.2.3.arm64_tahoe.bottle.tar.gz"

# assets - the file names in the stub release, sorted.
assets() {
    find "$STUB_RELEASE" -type f | sed 's|.*/||' | LC_ALL=C sort
}

name="creates the release and uploads under the remote names"
reset new
run "$script" "$repo" "$tag" "$dir"
if [[ $rc -ne 0 ]]; then
    fail "$name" "exit $rc: $err"
elif [[ "$(assets)" != "$remote_names" ]]; then
    fail "$name" "release holds: $(assets | tr '\n' ' ')"
elif [[ $out != "2 bottle(s) uploaded to $tag" ]]; then
    fail "$name" "printed '$out'"
elif ! grep -q "^gh release create $tag " "$STUB_LOG"; then
    fail "$name" "no release create: $(tr '\n' ';' < "$STUB_LOG")"
elif ! cmp -s "$dir/busysign--1.2.3.arm64_tahoe.bottle.tar.gz" \
    "$STUB_RELEASE/busysign-1.2.3.arm64_tahoe.bottle.tar.gz"; then
    fail "$name" "uploaded file differs from the bottle"
else
    ok "$name"
fi

name="re-run replaces the assets of an existing release"
reset rerun
mkdir -p "$STUB_RELEASE"
printf 'old\n' > "$STUB_RELEASE/busysign-1.2.3.arm64_sequoia.bottle.tar.gz"
run "$script" "$repo" "$tag" "$dir"
if [[ $rc -ne 0 ]]; then
    fail "$name" "exit $rc: $err"
elif grep -q "release create" "$STUB_LOG"; then
    fail "$name" "created the release again"
elif ! grep -q "^gh release upload $tag .*--clobber" "$STUB_LOG"; then
    fail "$name" "upload without --clobber: $(grep upload "$STUB_LOG")"
elif ! cmp -s "$dir/busysign--1.2.3.arm64_sequoia.bottle.tar.gz" \
    "$STUB_RELEASE/busysign-1.2.3.arm64_sequoia.bottle.tar.gz"; then
    fail "$name" "old asset kept"
else
    ok "$name"
fi

# expect_refused <name> <text in stderr> [no-gh] - exit 1; with no-gh, before any gh call.
expect_refused() {
    run "$script" "$repo" "$tag" "$dir"
    if [[ $rc -ne 1 ]]; then
        fail "$1" "exit $rc, expected 1: $err"
    elif [[ $err != *"$2"* ]]; then
        fail "$1" "stderr lacks '$2': $err"
    elif [[ ${3:-} == no-gh && -s $STUB_LOG ]]; then
        fail "$1" "called gh: $(tr '\n' ';' < "$STUB_LOG")"
    else
        ok "$1"
    fi
}

reset tampered
printf 'changed\n' >> "$dir/busysign--1.2.3.arm64_tahoe.bottle.tar.gz"
expect_refused "bottle that does not match its JSON is not uploaded" "sha256" no-gh

reset missing
rm "$dir/busysign--1.2.3.arm64_tahoe.bottle.tar.gz"
expect_refused "missing bottle file is not uploaded" "busysign--1.2.3.arm64_tahoe.bottle.tar.gz" no-gh

reset elsewhere
jq '.[].bottle.root_url = "https://github.com/someone/else/releases/download/busysign-1.2.3"' \
    "$dir/busysign--1.2.3.arm64_tahoe.bottle.json" > "$tmp/elsewhere.json"
mv "$tmp/elsewhere.json" "$dir/busysign--1.2.3.arm64_tahoe.bottle.json"
expect_refused "root_url of another release is not uploaded" "root_url" no-gh

reset slash
jq '.[].bottle.tags[].filename = "../busysign-1.2.3.arm64_tahoe.bottle.tar.gz"' \
    "$dir/busysign--1.2.3.arm64_tahoe.bottle.json" > "$tmp/slash.json"
mv "$tmp/slash.json" "$dir/busysign--1.2.3.arm64_tahoe.bottle.json"
expect_refused "remote name with a path is not uploaded" "file name" no-gh

reset dropped
STUB_DROP="busysign-1.2.3.arm64_tahoe.bottle.tar.gz"
expect_refused "asset missing after the upload fails" "busysign-1.2.3.arm64_tahoe.bottle.tar.gz"

reset corrupt
STUB_CORRUPT="busysign-1.2.3.arm64_sequoia.bottle.tar.gz"
expect_refused "asset with another digest fails" "busysign-1.2.3.arm64_sequoia.bottle.tar.gz"

reset empty
rm "$dir"/*.json
expect_refused "no bottle JSON fails" "no bottle" no-gh

reset usage
run "$script" "$repo" "$tag"
if [[ $rc -ne 2 ]]; then fail "missing directory exits 2" "exit $rc"; else ok "missing directory exits 2"; fi
run "$script" "$repo" "v1.2.3" "$dir"
if [[ $rc -ne 2 ]]; then fail "malformed release tag exits 2" "exit $rc"; else ok "malformed release tag exits 2"; fi

[[ $failures -eq 0 ]]
