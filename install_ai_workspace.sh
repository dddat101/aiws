#!/usr/bin/env bash
# Backward-compatible wrapper delegating to unified ai-workspace CLI
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AI_WORKSPACE_BIN="${SCRIPT_DIR}/ai-workspace"

if [[ ! -x "${AI_WORKSPACE_BIN}" ]]; then
    printf "[!] Error: Master binary '%s' not found or not executable.\n" "${AI_WORKSPACE_BIN}" >&2
    exit 1
fi

exec "${AI_WORKSPACE_BIN}" init "$@"
