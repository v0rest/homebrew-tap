#!/usr/bin/env bash
# Tests for scripts/test-formula.sh with stub brew and swift commands; nothing is installed.
# Usage: scripts/tests/test-test-formula.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../test-formula.sh"
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

# Stubs log every call to $STUB_LOG; brew fails the subcommand named in $STUB_FAIL.
stubs="$tmp/bin"
mkdir -p "$stubs"
cat > "$stubs/brew" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "$STUB_LOG"
case "$1" in
    --repository) echo "$STUB_REPO" ;;
    "$STUB_FAIL") exit 1 ;;
esac
EOF
cat > "$stubs/swift" <<'EOF'
#!/usr/bin/env bash
echo "swift $*" >> "$STUB_LOG"
echo "Swift version 6.0 (stub)"
EOF
chmod +x "$stubs/brew" "$stubs/swift"
PATH="$stubs:$PATH"
export PATH STUB_LOG STUB_REPO STUB_FAIL

# Never let the script reach the real brew.
if [[ "$(command -v brew)" != "$stubs/brew" || "$(command -v swift)" != "$stubs/swift" ]]; then
    echo "FAIL test-formula: stub brew/swift are not first in PATH, not running"
    exit 1
fi

formula="$tmp/busysign.rb"
printf 'class Busysign < Formula\nend\n' > "$formula"

# reset <name> - a fresh log and Homebrew repository for one case.
reset() {
    STUB_LOG="$tmp/$1.log"
    STUB_REPO="$tmp/$1-repo"
    STUB_FAIL=""
    : > "$STUB_LOG"
}

name="installs, tests and audits after printing the Swift version"
reset pass
run env GITHUB_ACTIONS=true "$script" "$formula"
expected="swift --version
brew --repository
brew install --build-from-source v0rest/tap/busysign
brew test v0rest/tap/busysign
brew audit --strict --formula v0rest/tap/busysign"
if [[ $rc -ne 0 ]]; then
    fail "$name" "exit $rc: $err"
elif [[ "$(cat "$STUB_LOG")" != "$expected" ]]; then
    fail "$name" "calls were: $(tr '\n' ';' < "$STUB_LOG")"
elif [[ $out != *"Swift version 6.0 (stub)"* ]]; then
    fail "$name" "swift --version not printed"
elif ! cmp -s "$formula" "$STUB_REPO/Library/Taps/v0rest/homebrew-tap/Formula/busysign.rb"; then
    fail "$name" "formula not copied into the tap"
else
    ok "$name"
fi

for step in install test audit; do
    name="stops when brew $step fails"
    reset "fail-$step"
    STUB_FAIL="$step"
    run env GITHUB_ACTIONS=true "$script" "$formula"
    last="$(tail -n 1 "$STUB_LOG")"
    if [[ $rc -eq 0 ]]; then
        fail "$name" "exit 0"
    elif [[ $last != "brew $step "* ]]; then
        fail "$name" "ran on after it: $last"
    else
        ok "$name"
    fi
done

name="refuses to run outside GitHub Actions"
reset outside
run env GITHUB_ACTIONS= "$script" "$formula"
if [[ $rc -ne 2 ]]; then
    fail "$name" "exit $rc, expected 2"
elif [[ -s $STUB_LOG ]]; then
    fail "$name" "called: $(tr '\n' ';' < "$STUB_LOG")"
else
    ok "$name"
fi

name="missing formula exits 2"
reset missing
run env GITHUB_ACTIONS=true "$script" "$tmp/nope.rb"
if [[ $rc -ne 2 ]]; then
    fail "$name" "exit $rc, expected 2"
elif [[ -s $STUB_LOG ]]; then
    fail "$name" "called: $(tr '\n' ';' < "$STUB_LOG")"
else
    ok "$name"
fi

[[ $failures -eq 0 ]]
