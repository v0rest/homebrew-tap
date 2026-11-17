#!/usr/bin/env bash
# Upload bottles to the tap release under Homebrew's download names (release created if needed); checks each digest.
# Usage: scripts/upload-bottles.sh <owner/repo> <busysign-X.Y.Z> <dir with the bottles and their *.bottle.json>
set -euo pipefail

usage() {
    echo "usage: $0 <owner/repo> <busysign-X.Y.Z> <bottle-dir>" >&2
    exit 2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 3 ]] || usage
repo="$1"
release="$2"
dir="$3"
repo_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
release_re='^busysign-[0-9]+\.[0-9]+\.[0-9]+$'
[[ $repo =~ $repo_re && $release =~ $release_re && -d $dir ]] || usage

# Every JSON from `brew bottle --json`: its bottle must exist, match its sha256 and belong to this release.
root_url="https://github.com/$repo/releases/download/$release"
name_re='^[A-Za-z0-9_.-]+\.bottle(\.[0-9]+)?\.tar\.gz$'
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
expected=""
count=0
for json in "$dir"/*.bottle.json; do
    [[ -f $json ]] || continue
    this_root="$(jq -r '.[].bottle.root_url' "$json")"
    [[ $this_root == "$root_url" ]] || fail "$json has root_url $this_root, not $root_url"
    for tag in $(jq -r '.[].bottle.tags | keys[]' "$json"); do
        local_name="$(jq -r --arg t "$tag" '.[].bottle.tags[$t].local_filename' "$json")"
        remote="$(jq -r --arg t "$tag" '.[].bottle.tags[$t].filename' "$json")"
        sha="$(jq -r --arg t "$tag" '.[].bottle.tags[$t].sha256' "$json")"
        [[ $local_name =~ $name_re ]] || fail "local file name '$local_name' in $json is not a plain bottle file name"
        [[ $remote =~ $name_re ]] || fail "remote file name '$remote' in $json is not a plain bottle file name"
        [[ -f $dir/$local_name ]] || fail "no $dir/$local_name for $json"
        actual="$(shasum -a 256 "$dir/$local_name" | cut -d' ' -f1)"
        [[ $actual == "$sha" ]] || fail "$local_name has sha256 $actual, $json says $sha"
        [[ ! -e $stage/$remote ]] || fail "two bottles named $remote"
        cp "$dir/$local_name" "$stage/$remote"
        expected="$expected$remote $sha"$'\n'
        count=$((count + 1))
    done
done
[[ $count -gt 0 ]] || fail "no bottle JSON in $dir"

if ! gh release view "$release" -R "$repo" > /dev/null 2>&1; then
    gh release create "$release" -R "$repo" --title "$release" \
        --notes "Bottles for ${release/-/ }, built and uploaded by the bump workflow."
fi
gh release upload "$release" -R "$repo" --clobber "$stage"/*

# The formula may point at these bottles only when each one is there with the digest it was built with.
assets="$(gh release view "$release" -R "$repo" --json assets)"
while read -r remote sha; do
    [[ -n $remote ]] || continue
    state="$(jq -r --arg n "$remote" '.assets[] | select(.name == $n) | "\(.state) \(.digest)"' <<< "$assets")"
    [[ $state == "uploaded sha256:$sha" ]] || fail "asset $remote in $release is '$state', not uploaded sha256:$sha"
done <<< "$expected"
echo "$count bottle(s) uploaded to $release"
