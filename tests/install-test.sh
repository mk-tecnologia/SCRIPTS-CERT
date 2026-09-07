#!/usr/bin/env bash
set -euo pipefail
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$REPO_DIR/install.sh"
# Simulate the remote manifest without installing or requiring network access.
curl() {
    [ "${FETCH_FAIL:-false}" = false ] || return 22
    printf '%s\n' "$MANIFEST"
}
# Version selection must not depend on the system awk implementation.
awk() { return 99; }
MANIFEST=$'# Versões suportadas; tags históricas\nv2.5.4\r\nv2.5.4\n'
[ "$(supported_versions)" = v2.5.4 ]
MANIFEST=$(cat "$REPO_DIR/supported-versions.txt")
[ "$(supported_versions)" = v2.5.4 ]
ASSUME_YES=true
select_remote_version
[ "$REQUESTED_VERSION" = v2.5.4 ]
REQUESTED_VERSION=''
ASSUME_YES=false
OUTPUT=$(select_remote_version <<< '')
[[ "$OUTPUT" == *'1) v2.5.4'* ]]
[[ "$OUTPUT" != *'0) main'* ]]
for MANIFEST in '' 'v2.5.4
invalid' '# empty'; do
    if (select_remote_version) >/dev/null 2>&1; then
        die 'Invalid/empty manifest was accepted'
    fi
done
FETCH_FAIL=true
if (select_remote_version) >/dev/null 2>&1; then
    die 'Network failure was accepted'
fi
REQUESTED_VERSION=main
select_remote_version
[ "$REQUESTED_VERSION" = main ]
printf 'Installer version selection tests passed\n'
