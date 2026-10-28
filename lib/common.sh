#!/usr/bin/env bash
# lib/common.sh - Core shared environment, path resolution, and logging utilities
set -Eeuo pipefail

# Error trap reporting exact line and failing command
setup_err_trap() {
    trap 'printf "[!] Error on line %d: command \"%s\" exited with status %d\n" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
}

# Structured logging functions (directed to stderr for safe command substitution)
log_info()    { printf "[*] %s\n" "$*" >&2; }
log_success() { printf "[✓] %s\n" "$*" >&2; }
log_warn()    { printf "[!] Warning: %s\n" "$*" >&2; }
log_error()   { printf "[!] Error: %s\n" "$*" >&2; }

# Command runner supporting dry-run
DRY_RUN="${DRY_RUN:-false}"
run_cmd() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        printf "[DRY-RUN] Would execute: %s\n" "$*"
        return 0
    fi
    "$@"
}

# Safe regex escape helper
escape_regex() {
    printf '%s\n' "$1" | sed 's/[.[\*^$()+?{|]/\\&/g'
}

# Resolve canonical workspace environment variables
resolve_workspace_env() {
    local target_arg="${1:-}"

    if [[ -n "${target_arg}" ]]; then
        if [[ ! -d "${target_arg}" ]]; then
            log_error "Target directory '${target_arg}' does not exist."
            return 1
        fi
        CODEBASE_ROOT="$(cd -- "${target_arg}" && (git rev-parse --show-toplevel 2>/dev/null || pwd -P))"
    else
        CODEBASE_ROOT="${TARGET_CODEBASE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"
    fi

    PROJECT_NAME="$(basename -- "${CODEBASE_ROOT}")"
    EXTERNAL_BASE="${AI_WORKSPACE_DIR:-${HOME}/.ai_workspaces/${PROJECT_NAME}}"
    AI_DIR="${EXTERNAL_BASE}/.ai"
    DOMAINS_DIR="${AI_DIR}/domains"
    INDEX_FILE="${AI_DIR}/index.md"
    CONVENTIONS_FILE="${AI_DIR}/conventions.md"
    LESSONS_FILE="${AI_DIR}/lessons_learned.md"

    export CODEBASE_ROOT PROJECT_NAME EXTERNAL_BASE AI_DIR DOMAINS_DIR INDEX_FILE CONVENTIONS_FILE LESSONS_FILE
    return 0
}
