#!/usr/bin/env bash
# Backward-compatible wrapper delegating to unified ai-workspace CLI
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Locate master binary
AI_WORKSPACE_BIN=""
if [[ -x "${SCRIPT_DIR}/../ai-workspace" ]]; then
    AI_WORKSPACE_BIN="${SCRIPT_DIR}/../ai-workspace"
elif [[ -x "${SCRIPT_DIR}/ai-workspace" ]]; then
    AI_WORKSPACE_BIN="${SCRIPT_DIR}/ai-workspace"
elif command -v ai-workspace >/dev/null 2>&1; then
    AI_WORKSPACE_BIN="$(command -v ai-workspace)"
else
    printf "[!] Error: Master binary 'ai-workspace' not found.\n" >&2
    exit 1
fi

exec "${AI_WORKSPACE_BIN}" bootstrap "$@"
