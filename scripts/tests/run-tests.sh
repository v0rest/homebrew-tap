#!/usr/bin/env bash
# Run every scripts/tests/test-*.sh and fail if any of them fails.
# Usage: scripts/tests/run-tests.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
status=0
for test in "$here"/test-*.sh; do
    echo "== $(basename "$test")"
    "$test" || status=1
done
if [[ $status -ne 0 ]]; then
    echo "some tests failed"
fi
exit "$status"
