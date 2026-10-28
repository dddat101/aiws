# AI Workspace (`aiws`) Integration Plan

## Executive Summary
The `aiws` (`ai-workspace`) architecture establishes a self-evolving, out-of-tree knowledge base (`~/.ai_workspaces/<project_name>`) decoupled from the target codebase's version control. It combines multi-language static symbol extraction (`lib/symbol_extractor.sh`), a confidence-driven lifecycle state machine (`[SKELETON]` $\rightarrow$ `[STATIC]` $\rightarrow$ `[VERIFIED]` $\rightarrow$ `[NEEDS_REVERIFY]` in `lib/knowledge_registry.sh`), and the `codebase-memory` Agent Skill to minimize token consumption while preventing static-analysis hallucinations.

This document outlines a **5-phase rollout plan** to harden `aiws` and integrate it seamlessly into a large production codebase.

---

## Phase 1: Pre-Integration Hardening
Before provisioning the workspace on a live production repository, five technical edge cases in `aiws` have been hardened to prevent conflicts with existing Git workflows, global symlinks, and repository layouts:

1. **Resolve Symlinks for Global CLI Invocation (`ai-workspace:5-6`):**
   * **Issue:** Computing `SCRIPT_DIR` directly from `dirname "${BASH_SOURCE[0]}"` fails to resolve symlinked executables (e.g., `~/.local/bin/ai-workspace`), causing `lib/common.sh` lookup to fail.
   * **Remediation:** Resolve `SCRIPT_PATH` via `readlink -f -- "${BASH_SOURCE[0]}"` before computing `SCRIPT_DIR`.
2. **Prevent Git Hook Overwrites (`lib/workspace_provisioner.sh:178-205`):**
   * **Issue:** Direct `cp` commands overwrite existing `.git/hooks/pre-commit` and `post-merge` scripts, potentially destroying team-mandated linters, `checkpatch` scripts, or CI hooks.
   * **Remediation:** Check if the target hook file already exists. If it does, append the `ai-workspace` hook invocation block idempotently rather than overwriting the file.
3. **Support Git Worktrees, Submodules, and Multi-Repo Trees (`lib/workspace_provisioner.sh:160-176`):**
   * **Issue:** Checking `[[ -d "${CODEBASE_ROOT}/.git" ]]` evaluates to `false` in Git worktrees, submodules, or `repo`-managed trees where `.git` is a pointer file (`gitdir: ...`), causing `.git/info/exclude` and hook installation to be skipped.
   * **Remediation:** Verify worktrees with `git -C "${CODEBASE_ROOT}" rev-parse --is-inside-work-tree` and resolve the shared Git directory dynamically via `git rev-parse --path-format=absolute --git-common-dir`.
4. **Fix Subdirectory Path Resolution & Symlink Self-Healing (`ai-workspace:178-199`, `ai-workspace:241-244`):**
   * **Issue:** Relative paths passed to `bootstrap` from a subdirectory fail if evaluated after changing directories without normalization, or fail during `--dry-run` when `cd -- "${CODEBASE_ROOT}"` is skipped. Additionally, `git clean -fdX` removes ignored symlinks (`.ai`, `AGENTS.md`).
   * **Remediation:** Normalize target paths relative to `CODEBASE_ROOT` via `realpath --relative-to="${CODEBASE_ROOT}"` prior to `cd -- "${CODEBASE_ROOT}"` (outside the `DRY_RUN` conditional), and auto-heal missing `.ai` and `AGENTS.md` symlinks during both `bootstrap` and `sync`.
5. **Preserve `[STATIC]` Status During `reindex` & `status` (`lib/knowledge_registry.sh:105-116`, `lib/knowledge_registry.sh:160-192`):**
   * **Issue:** `registry_reindex` lacked a branch checking for `[STATIC]` and omitted `STATIC` from its `sed` replacement pattern, inadvertently downgrading `[STATIC]` domains back to `[SKELETON]`.
   * **Remediation:** Add explicit state recognition and `sed` pattern support for `[STATIC]` domains in `registry_reindex` and `registry_print_status`.

---

## Phase 2: Global CLI Installation & Zero-Footprint Provisioning
Deploy `ai-workspace` as a machine-wide utility rather than copying tool scripts into individual repositories:

1. **Verify Dependencies & Expose CLI Globally:**
   ```bash
   # Ensure Universal Ctags is installed for accurate C/C++ AST/tag extraction
   ctags --version | grep -i "Universal"

   # Link the CLI into user PATH
   mkdir -p ~/.local/bin
   ln -sfn /path/to/aiws/ai-workspace ~/.local/bin/ai-workspace
   ```
2. **Execute a Dry-Run on the Target Repository:**
   ```bash
   ai-workspace init --dry-run /path/to/target/codebase
   ```
   Verify that `~/.ai_workspaces/<project_name>` does not collide with an existing workspace. If a naming conflict exists, override the target path via `export AI_WORKSPACE_DIR=~/.ai_workspaces/<custom_project_name>`.
3. **Provision & Verify Git Isolation:**
   ```bash
   ai-workspace init /path/to/target/codebase
   cd /path/to/target/codebase

   # Verify 3 mandatory isolation checks:
   git status                                                 # Must be 100% clean (no .ai or AGENTS.md)
   ls -la ~/.agents/skills/codebase-memory                    # Global skill symlink verified
   git -C ~/.ai_workspaces/$(basename "$PWD") log --oneline   # Dedicated AI knowledge repo initialized
   ```

---

## Phase 3: Cross-Cutting Architectural Foundations
Before indexing individual modules, populate global architectural rules so the AI Agent respects project-wide invariants from the first prompt:

1. **Populate `.ai/conventions.md`:**
   * **Memory Ownership:** Document custom allocation/deallocation wrappers (e.g., `kmalloc`/`free`, DMA coherent buffers, packet buffer pools) and caller vs. callee ownership semantics on error return paths.
   * **Concurrency & Locking:** Distinguish interrupt/tasklet contexts (`spin_lock_irqsave`) from process contexts (`mutex_lock`), and specify lock ordering hierarchies to prevent deadlocks.
   * **IPC & Data Models:** Define cross-daemon communication protocols and parameter serialization rules (e.g., Unix domain sockets, Netlink, IOCTL, RPC schema handlers).
2. **Normalize Routing Keywords in `.ai/index.md`:**
   * Enrich the `Keywords & Symptoms` column for `conventions` with daemon names, protocol identifiers, and error symptoms so the Agent reliably loads global rules prior to code generation or review.

---

## Phase 4: Incremental Domain Decomposition & Rolling Bootstrap
Avoid running `bootstrap` indiscriminately across the entire repository at once, which creates excessive `[SKELETON]` files and dilutes `.ai/index.md` routing accuracy. Instead, roll out domains in **three targeted waves** aligned with active engineering tasks:

| Rollout Wave | Target Subsystem | Naming Convention | Example Command |
| :--- | :--- | :--- | :--- |
| **Wave 1 (High Priority)** | Core C/C++ modules under active debugging or feature work | `<subsystem>/<module>` (e.g., `net/ipv6_ndp`, `net/driver`) | `ai-workspace bootstrap net/ipv6_ndp src/net/ipv6/ include/net/ndp.h` |
| **Wave 2 (Verification)** | Python test suites, fixtures, and automation harnesses | `tests/<suite_name>` | `ai-workspace bootstrap tests/qos_suite tests/suites/qos/` |
| **Wave 3 (Infrastructure)** | Shell/Bash firmware build scripts, image packers, CI pipelines | `ci/<pipeline_name>` | `ai-workspace bootstrap ci/image_pack scripts/build/` |

### Standard Post-Bootstrap Workflow
1. **Automatic Pruning & Keyword Enrichment:** `bootstrap` automatically caps internal/static helper symbols (`MAX_STATIC_SYMBOLS=80`), excludes trivial header `static inline` helpers, and populates `.ai/index.md` with top discovered symbols for high-accuracy Tier-1 routing.
2. **Populate Execution Flows:** Prompt the AI Agent using **Pattern 1** (from `README.md`) to inspect entry-point functions via `./.ai/ai-workspace slice <symbol>`, populate `## 1. Core Execution Flows` and `## 2. Data Structures & Invariants`, and promote the status from `[SKELETON]` to `[STATIC]` (or `[VERIFIED]` once validated against runtime logs).

---

## Phase 5: Daily Closed-Loop Operations
Once the initial 2–3 core domains are established, maintain accuracy through continuous closed-loop operation:

1. **Automated Staleness Detection:**
   * Every `git commit` or `git pull` in the target repository triggers `pre-commit` / `post-merge` hooks, invoking `ai-workspace sync`.
   * Whenever a domain carries the `[NEEDS_REVERIFY]` flag, instruct the AI Agent to inspect `git diff` on the modified source files and update line numbers and call graphs before answering new queries.
2. **Compound Runtime Learning:**
   * After resolving a non-obvious runtime bug (e.g., hidden macro side effects, runtime `ops->*` function pointer overrides, or race conditions), instruct the Agent to record the symptom and root cause in `.ai/lessons_learned.md` and promote the corresponding domain flow to `[VERIFIED]`.
3. **Periodic Maintenance:**
   * Run `ai-workspace status` weekly to audit `[VERIFIED]` vs. `[NEEDS_REVERIFY]` ratios, and run `ai-workspace reindex` following major directory refactorings.

---

## Integration Acceptance Checklist

| Verification Item | Command | Acceptance Criteria |
| :--- | :--- | :--- |
| **Git Working Tree Isolation** | `git status --ignored` | Only `/.ai` and `/AGENTS.md` appear under `.git/info/exclude`; working tree remains completely clean. |
| **Resilience to `git clean`** | `git clean -ndx` | Persistent data in `~/.ai_workspaces/<project>` is untouched; symlinks auto-heal on next hook/CLI run. |
| **Agent Skill Activation** | Launch AI CLI in target repo and query a bootstrapped module | Agent reads `.ai/index.md` first and jumps directly to `file:line` coordinates instead of brute-force scanning. |
| **Staleness Hook Trigger** | Modify a mapped `.c` file and run `git commit` | Affected domain automatically transitions to `[NEEDS_REVERIFY]` and commits to the isolated AI Git repo. |