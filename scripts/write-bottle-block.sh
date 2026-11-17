#!/usr/bin/env bash
# Add the bottle block to a formula from `brew bottle --json` files, as `brew bottle --merge --write` writes it.
# Usage: scripts/write-bottle-block.sh <formula-path> <bottle.json>...
set -euo pipefail

# The form follows Homebrew's dev-cmd/bottle.rb (BOTTLE_ERB, bottle_output, generate_sha256_line, merge) and
# BottleSpecification#checksums for the order: arm64 first, newest macOS first. One sha256 line per tag; a set of
# identical bottles, which `brew bottle --merge` would turn into an `all:` bottle, is refused instead.

usage() {
    echo "usage: $0 <formula-path> <bottle.json>..." >&2
    exit 2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -ge 2 ]] || usage
formula="$1"
shift
[[ -f $formula ]] || { echo "error: no formula at $formula" >&2; exit 2; }

if grep -qx '  bottle do' "$formula"; then
    fail "$formula already has a bottle block"
fi
[[ "$(grep -c '^  license ' "$formula" || true)" -eq 1 ]] || fail "$formula needs exactly one license line"
[[ -z "$(grep -A1 '^  license ' "$formula" | sed -n 2p)" ]] || fail "$formula needs a blank line after license"

num='([0-9]+\.[0-9]+\.[0-9]+)'
url_re='^  url "https://github\.com/v0rest/busysign/releases/download/v'"$num"'/busysign-'"$num"'\.tar\.gz"$'
version=""
while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ $url_re ]]; then
        version="${BASH_REMATCH[1]}"
    fi
done < "$formula"
[[ -n $version ]] || fail "cannot read the version from the url in $formula"

# macos_version <name> - the macOS version Homebrew sorts a bottle tag by.
macos_version() {
    case $1 in
        golden_gate) echo 27 ;;
        tahoe) echo 26 ;;
        sequoia) echo 15 ;;
        sonoma) echo 14 ;;
        ventura) echo 13 ;;
        monterey) echo 12 ;;
        big_sur) echo 11 ;;
        *) return 1 ;;
    esac
}

sha_re='^[0-9a-f]{64}$'
cellar_path_re='^/[A-Za-z0-9._/-]+$'
# The bottles live in this tap's release for the version, where scripts/upload-bottles.sh puts them.
root_url="https://github.com/v0rest/homebrew-tap/releases/download/busysign-$version"
rebuild=""
# One record per tag: <sort key>|<tag>|<cellar>|<sha256>
records=""
for json in "$@"; do
    [[ -f $json ]] || fail "no $json"
    [[ "$(jq 'keys | length' "$json")" -eq 1 ]] || fail "$json must describe one formula"
    name="$(jq -r '.[].formula.name' "$json")"
    [[ $name == busysign ]] || fail "$json is a bottle of '$name', not busysign"
    pkg_version="$(jq -r '.[].formula.pkg_version' "$json")"
    [[ $pkg_version == "$version" ]] || fail "$json is a bottle of busysign $pkg_version, the formula has $version"

    this_root="$(jq -r '.[].bottle.root_url' "$json")"
    [[ $this_root == "$root_url" ]] || fail "$json has root_url '$this_root', expected $root_url"
    this_rebuild="$(jq -r '.[].bottle.rebuild' "$json")"
    [[ $this_rebuild =~ ^[0-9]+$ ]] || fail "$json has an unexpected rebuild '$this_rebuild'"
    [[ -n $rebuild ]] || rebuild="$this_rebuild"
    [[ $this_rebuild == "$rebuild" ]] || fail "$json has rebuild $this_rebuild, another file has $rebuild"

    suffix=""
    [[ $rebuild -gt 0 ]] && suffix=".$rebuild"
    bottle_cellar="$(jq -r '.[].bottle.cellar // ""' "$json")"
    for tag in $(jq -r '.[].bottle.tags | keys[]' "$json"); do
        case $tag in
            arm64_*) priority=3; os="${tag#arm64_}" ;;
            *) priority=2; os="$tag" ;;
        esac
        os_version="$(macos_version "$os")" || fail "unknown bottle tag $tag in $json"
        case "|$records" in
            *"|$tag|"*) fail "two bottles for $tag" ;;
        esac

        sha="$(jq -r --arg t "$tag" '.[].bottle.tags[$t].sha256' "$json")"
        [[ $sha =~ $sha_re ]] || fail "malformed sha256 for $tag in $json"
        cellar="$(jq -r --arg t "$tag" '.[].bottle.tags[$t].cellar // ""' "$json")"
        [[ -n $cellar ]] || cellar="$bottle_cellar"
        case $cellar in
            any | any_skip_relocation | "") ;;
            *) [[ $cellar =~ $cellar_path_re ]] || fail "unexpected cellar '$cellar' for $tag in $json" ;;
        esac

        # Homebrew downloads <root_url>/<name>-<version>.<tag>.bottle[.<rebuild>].tar.gz (Bottle::Filename).
        remote="busysign-$version.$tag.bottle$suffix.tar.gz"
        filename="$(jq -r --arg t "$tag" '.[].bottle.tags[$t].filename' "$json")"
        [[ $filename == "$remote" ]] || fail "remote file name for $tag is '$filename', Homebrew downloads $remote"

        records="$records$priority.${os_version}_$tag|$tag|$cellar|$sha"$'\n'
    done
done

count="$(printf '%s' "$records" | grep -c .)"
if [[ $count -gt 1 && "$(printf '%s' "$records" | cut -d'|' -f3,4 | sort -u | grep -c .)" -eq 1 ]]; then
    fail "all bottles are identical; brew bottle --merge would write an all: bottle, which this script does not"
fi

# cellar_arg <cellar> - the cellar: argument of a sha256 line, empty for Homebrew's default cellars.
cellar_arg() {
    case $1 in
        any | any_skip_relocation) echo "cellar: :$1," ;;
        "" | /usr/local/Cellar | /opt/homebrew/Cellar | /home/linuxbrew/.linuxbrew/Cellar) echo "" ;;
        *) echo "cellar: \"$1\"," ;;
    esac
}

# pad <text> <width> - the text followed by spaces up to the width.
pad() {
    local text="$1"
    while [[ ${#text} -lt $2 ]]; do
        text="$text "
    done
    printf '%s' "$text"
}

# Columns as generate_sha256_line lines them up: tags after the widest cellar argument, digests after the widest tag.
sorted="$(printf '%s' "$records" | LC_ALL=C sort -r -t'|' -k1,1)"
tag_column=0
tag_width=0
while IFS='|' read -r _ tag cellar _; do
    arg="$(cellar_arg "$cellar")"
    if [[ -n $arg && $((${#arg} + 1)) -gt $tag_column ]]; then
        tag_column=$((${#arg} + 1))
    fi
    if [[ ${#tag} -gt $tag_width ]]; then
        tag_width=${#tag}
    fi
done <<< "$sorted"
digest_column=$((tag_column + tag_width + 2))

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
{
    echo "  bottle do"
    echo "    root_url \"$root_url\""
    if [[ $rebuild -gt 0 ]]; then
        echo "    rebuild $rebuild"
    fi
    while IFS='|' read -r _ tag cellar sha; do
        line="$(pad "sha256 $(cellar_arg "$cellar")" $((tag_column + 7)))"
        line="$(pad "$line$tag:" $((digest_column + 7)))"
        echo "    $line\"$sha\""
    done <<< "$sorted"
    echo "  end"
} > "$work/block"

# After the blank line that follows license, then a blank line, where add_bottle_block puts it.
awk '
    FNR == NR { block = block $0 "\n"; next }
    { print }
    after_license && $0 == "" { printf "%s\n", block; after_license = 0 }
    /^  license / { after_license = 1; next }
    { after_license = 0 }
' "$work/block" "$formula" > "$work/formula"
chmod 644 "$work/formula"
mv "$work/formula" "$formula"
echo "bottle block for $count tag(s) written to $formula"
