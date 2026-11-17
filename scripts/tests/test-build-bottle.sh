#!/usr/bin/env bash
# Tests for scripts/build-bottle.sh with a stub brew and a stub check-poured.sh; nothing is installed.
# Usage: scripts/tests/test-build-bottle.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
ok() { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; failures=$((failures + 1)); }

# run <command...> - sets $err (stderr) and $rc without stopping on failure; stdout is dropped.
run() {
    set +e
    "$@" > /dev/null 2>"$tmp/stderr"
    rc=$?
    set -e
    err="$(cat "$tmp/stderr")"
}

# The script runs from a copy next to a stub check-poured.sh that only logs.
mkdir -p "$tmp/scripts"
cp "$here/../build-bottle.sh" "$tmp/scripts/build-bottle.sh"
script="$tmp/scripts/build-bottle.sh"
cat > "$tmp/scripts/check-poured.sh" <<'EOF'
#!/usr/bin/env bash
echo "check-poured $*" >> "$STUB_LOG"
EOF
chmod +x "$tmp/scripts/check-poured.sh"

# Stub brew logs every call, with " [HOMEBREW_DEVELOPER=...]" when that is set; `--version` prints $STUB_VERSION;
# `bottle` writes a bottle and its JSON into the current directory like the real one; a call matching the pattern
# in $STUB_FAIL fails.
stubs="$tmp/bin"
mkdir -p "$stubs"
cat > "$stubs/brew" <<'EOF'
#!/usr/bin/env bash
line="brew $*"
[[ $1 == bottle ]] && line="$line (in $PWD)"
[[ -n ${HOMEBREW_DEVELOPER+set} ]] && line="$line [HOMEBREW_DEVELOPER=$HOMEBREW_DEVELOPER]"
echo "$line" >> "$STUB_LOG"
# shellcheck disable=SC2053
[[ -n ${STUB_FAIL:-} && "$*" == $STUB_FAIL ]] && exit 1
[[ $1 == --version ]] && echo "$STUB_VERSION"
if [[ $1 == bottle ]]; then
    printf 'bottle\n' > busysign--1.2.3.arm64_sequoia.bottle.tar.gz
    printf '{"v0rest/tap/busysign": {"bottle": {"tags": {"arm64_sequoia": %s}}}}\n' \
        '{"filename": "busysign-1.2.3.arm64_sequoia.bottle.tar.gz",
          "local_filename": "busysign--1.2.3.arm64_sequoia.bottle.tar.gz"}' \
        > busysign--1.2.3.arm64_sequoia.bottle.json
fi
exit 0
EOF
chmod +x "$stubs/brew"
PATH="$stubs:$PATH"
unset HOMEBREW_DEVELOPER
export PATH STUB_LOG STUB_FAIL STUB_VERSION
if [[ "$(command -v brew)" != "$stubs/brew" ]]; then
    echo "FAIL build-bottle: stub brew is not first in PATH, not running"
    exit 1
fi

# reset <name> - a fresh log and output directory for one case, Homebrew 7.0.13.
reset() {
    STUB_LOG="$tmp/$1.log"
    STUB_FAIL=""
    STUB_VERSION="Homebrew 7.0.13"
    outdir="$tmp/$1/bottle"
    : > "$STUB_LOG"
}

# expected <pour suffix> - the calls of a full run; the pour line ends with the suffix.
expected() {
    echo "brew --version
brew trust --tap v0rest/tap
brew uninstall v0rest/tap/busysign
brew install --build-bottle v0rest/tap/busysign
brew bottle --json --no-rebuild --root-url=https://github.com/v0rest/homebrew-tap/releases/download/busysign-1.2.3 \
v0rest/tap/busysign (in $outdir)
brew uninstall v0rest/tap/busysign
brew install $outdir/busysign--1.2.3.arm64_sequoia.bottle.tar.gz$1
check-poured 1.2.3"
}

# Homebrew 7.0.13 and later pour a bottle path as is; before 7.0.13 the pour alone needs HOMEBREW_DEVELOPER.
for case in "Homebrew 7.0.13|" "Homebrew 7.0.14-27-gabc1234|" "Homebrew 8.0.0|" "Homebrew 7.1.0|" \
    "Homebrew 7.0.12| [HOMEBREW_DEVELOPER=1]" "Homebrew 6.9.99| [HOMEBREW_DEVELOPER=1]"; do
    brew_version="${case%%|*}"
    suffix="${case#*|}"
    name="builds, bottles, pours and checks in order on $brew_version"
    reset "pass-$(echo "$brew_version" | tr -c '[:alnum:]' '-')"
    STUB_VERSION="$brew_version"
    run env GITHUB_ACTIONS=true "$script" 1.2.3 "$outdir"
    if [[ $rc -ne 0 ]]; then
        fail "$name" "exit $rc: $err"
    elif [[ "$(cat "$STUB_LOG")" != "$(expected "$suffix")" ]]; then
        fail "$name" "calls were: $(tr '\n' ';' < "$STUB_LOG")"
    else
        ok "$name"
    fi
done

name="unreadable Homebrew version stops before any change"
reset no-version
STUB_VERSION="Homebrew >=4.3.0 (shallow or no git repository)"
run env GITHUB_ACTIONS=true "$script" 1.2.3 "$outdir"
if [[ $rc -ne 1 ]]; then
    fail "$name" "exit $rc, expected 1"
elif [[ "$(cat "$STUB_LOG")" != "brew --version" ]]; then
    fail "$name" "calls were: $(tr '\n' ';' < "$STUB_LOG")"
else
    ok "$name"
fi

for pattern in "trust *" "install --build-bottle*" "bottle *" "install /*"; do
    name="stops when 'brew $pattern' fails"
    reset "fail-$(echo "$pattern" | tr -c '[:lower:]' '-')"
    STUB_FAIL="$pattern"
    run env GITHUB_ACTIONS=true "$script" 1.2.3 "$outdir"
    last="$(tail -n 1 "$STUB_LOG")"
    # shellcheck disable=SC2053
    if [[ $rc -eq 0 ]]; then
        fail "$name" "exit 0"
    elif [[ ${last#brew } != $pattern ]]; then
        fail "$name" "ran on after it: $last"
    else
        ok "$name"
    fi
done

name="refuses an output directory that is not empty"
reset not-empty
mkdir -p "$outdir"
printf 'old\n' > "$outdir/busysign--1.2.2.arm64_sequoia.bottle.json"
run env GITHUB_ACTIONS=true "$script" 1.2.3 "$outdir"
if [[ $rc -ne 2 ]]; then
    fail "$name" "exit $rc, expected 2"
elif [[ -s $STUB_LOG ]]; then
    fail "$name" "called: $(tr '\n' ';' < "$STUB_LOG")"
else
    ok "$name"
fi

name="refuses to run outside GitHub Actions"
reset outside
run env GITHUB_ACTIONS= "$script" 1.2.3 "$outdir"
if [[ $rc -ne 2 ]]; then
    fail "$name" "exit $rc, expected 2"
elif [[ -s $STUB_LOG ]]; then
    fail "$name" "called: $(tr '\n' ';' < "$STUB_LOG")"
else
    ok "$name"
fi

name="malformed version exits 2"
reset malformed
run env GITHUB_ACTIONS=true "$script" v1.2.3 "$outdir"
if [[ $rc -ne 2 || -s $STUB_LOG ]]; then fail "$name" "exit $rc"; else ok "$name"; fi

[[ $failures -eq 0 ]]
