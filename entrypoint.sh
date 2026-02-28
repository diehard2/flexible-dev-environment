#!/bin/bash
set -euo pipefail

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "$GITHUB_TOKEN" | gh auth login --hostname github.com --git-protocol ssh --with-token 2>/dev/null || true
fi

exec "$@"
