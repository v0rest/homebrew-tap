#!/usr/bin/env bash
# Tests for scripts/check-poured.sh with stub brew, xattr and codesign commands and a fake app.
# Usage: scripts/tests/test-check-poured.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../check-poured.sh"
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

stubs="$tmp/bin"
mkdir -p "$stubs"
cat > "$stubs/brew" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "info --json=v2 --installed") cat "$STUB_INFO" ;;
    "--prefix v0rest/tap/busysign") echo "$STUB_PREFIX" ;;
    *) echo "stub brew: unexpected $*" >&2; exit 9 ;;
esac
EOF
cat > "$stubs/xattr" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -r ]] || { echo "stub xattr: unexpected $*" >&2; exit 9; }
printf '%s' "$STUB_XATTR"
exit "${STUB_XATTR_RC:-0}"
EOF
cat > "$stubs/codesign" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2 $3" == "--verify --deep --strict" ]] || { echo "stub codesign: unexpected $*" >&2; exit 9; }
exit "${STUB_CODESIGN_RC:-0}"
EOF
chmod +x "$stubs/brew" "$stubs/xattr" "$stubs/codesign"
PATH="$stubs:$PATH"
export PATH STUB_INFO STUB_PREFIX STUB_XATTR STUB_XATTR_RC STUB_CODESIGN_RC STUB_APP_VERSION
if [[ "$(command -v brew)" != "$stubs/brew" || "$(command -v codesign)" != "$stubs/codesign" ]]; then
    echo "FAIL check-poured: stubs are not first in PATH, not running"
    exit 1
fi

STUB_PREFIX="$tmp/opt/busysign"
mkdir -p "$STUB_PREFIX/BusySign.app/Contents/MacOS"
cat > "$STUB_PREFIX/BusySign.app/Contents/MacOS/BusySign" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --version ]] && echo "$STUB_APP_VERSION"
EOF
chmod +x "$STUB_PREFIX/BusySign.app/Contents/MacOS/BusySign"

# info <installed-json-array> - brew info output with another formula and busysign's installed kegs.
info() {
    STUB_INFO="$tmp/info.json"
    cat > "$STUB_INFO" <<EOF
{"formulae": [
  {"name": "jq", "full_name": "jq", "installed": [{"version": "1.8.1", "poured_from_bottle": false}]},
  {"name": "busysign", "full_name": "v0rest/tap/busysign", "installed": $1}
], "casks": []}
EOF
}

# reset - a poured 1.2.3 that passes every check.
reset() {
    info '[{"version": "1.2.3", "built_as_bottle": true, "poured_from_bottle": true}]'
    STUB_XATTR="$STUB_PREFIX/BusySign.app: com.apple.provenance"
    STUB_XATTR_RC=0
    STUB_CODESIGN_RC=0
    STUB_APP_VERSION="1.2.3"
}

# expect <name> <exit> [text in stderr]
expect() {
    run "$script" 1.2.3
    if [[ $rc -ne $2 ]]; then
        fail "$1" "exit $rc, expected $2: $err"
    elif [[ -n ${3:-} && $err != *"$3"* ]]; then
        fail "$1" "stderr lacks '$3': $err"
    elif [[ $2 -eq 0 && $out != *"poured from a bottle"* ]]; then
        fail "$1" "printed '$out'"
    elif [[ $2 -ne 0 && -n $out ]]; then
        fail "$1" "printed '$out' on stdout"
    else
        ok "$1"
    fi
}

reset
expect "poured bottle passes" 0

reset
info '[{"version": "1.2.3", "built_as_bottle": true, "poured_from_bottle": false}]'
expect "built from source fails" 1 "not poured from a bottle"

reset
info '[]'
expect "not installed fails" 1 "installed"

reset
info '[{"version": "1.2.2", "poured_from_bottle": true}, {"version": "1.2.3", "poured_from_bottle": true}]'
expect "two installed versions fail" 1 "installed"

reset
info '[{"version": "1.2.2", "poured_from_bottle": true}]'
expect "other installed version fails" 1 "1.2.2"

reset
STUB_XATTR="$STUB_PREFIX/BusySign.app/Contents/MacOS/BusySign: com.apple.quarantine"
expect "quarantine attribute fails" 1 "com.apple.quarantine"

reset
STUB_XATTR_RC=1
expect "xattr failing fails" 1

reset
STUB_CODESIGN_RC=1
expect "codesign failure fails" 1 "codesign"

reset
STUB_APP_VERSION="1.2.2"
expect "wrong --version fails" 1 "--version"

reset
mv "$STUB_PREFIX/BusySign.app" "$tmp/moved.app"
expect "missing app fails" 1 "BusySign.app"
mv "$tmp/moved.app" "$STUB_PREFIX/BusySign.app"

reset
run "$script"
if [[ $rc -ne 2 ]]; then fail "missing version exits 2" "exit $rc"; else ok "missing version exits 2"; fi
run "$script" v1.2.3
if [[ $rc -ne 2 ]]; then fail "malformed version exits 2" "exit $rc"; else ok "malformed version exits 2"; fi

[[ $failures -eq 0 ]]
