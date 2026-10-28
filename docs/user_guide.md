# AI Workspace (`ai-workspace`) — Comprehensive User Guide

**Version:** 2.0.0  
**Audience:** Software Engineers, Tech Leads, and AI-Assisted Development Teams  
**Supported Languages:** C, C++, Python (including Pytest), Shell/Bash, and Polyglot Monorepos  

---

## Table of Contents
1. [Introduction & Core Concepts](#1-introduction--core-concepts)
2. [System Requirements & Installation](#2-system-requirements--installation)
3. [Quickstart: Setting Up a New Project](#3-quickstart-setting-up-a-new-project)
4. [Migrating an Existing Legacy Workspace](#4-migrating-an-existing-legacy-workspace)
5. [Complete CLI Command Reference](#5-complete-cli-command-reference)
   - [5.1 `init` — Provision Workspace](#51-init--provision-workspace)
   - [5.2 `migrate` — Upgrade Existing Workspace](#52-migrate--upgrade-existing-workspace)
   - [5.3 `bootstrap` — Extract Symbols & Create Domain Skeleton](#53-bootstrap--extract-symbols--create-domain-skeleton)
   - [5.4 `slice` — Surgical Source Code Extraction](#54-slice--surgical-source-code-extraction)
   - [5.5 `refresh-coords` — Auto-Heal Drifted Line Coordinates](#55-refresh-coords--auto-heal-drifted-line-coordinates)
   - [5.6 `sync` — Precision Staleness Tracking](#56-sync--precision-staleness-tracking)
   - [5.7 `reindex` — Reconcile Knowledge Routing Table](#57-reindex--reconcile-knowledge-routing-table)
   - [5.8 `status` — Inspect Health & Actionable Prompt Suggestions](#58-status--inspect-health--actionable-prompt-suggestions)
6. [Knowledge Base Structure & Lifecycle States](#6-knowledge-base-structure--lifecycle-states)
7. [Working with AI Coding Agents (`codebase-memory` Skill)](#7-working-with-ai-coding-agents-codebase-memory-skill)
8. [High-Leverage Prompt Engineering Catalog](#8-high-leverage-prompt-engineering-catalog)
9. [Environment Variables & Customization](#9-environment-variables--customization)
10. [Troubleshooting & FAQ](#10-troubleshooting--faq)

---

## 1. Introduction & Core Concepts

When working on large-scale repositories, AI coding agents often waste tens of thousands of tokens running broad `grep` or file scans, leading to high latency, context window exhaustion, and hallucinated call graphs. Furthermore, strict enterprise policies prohibit committing AI configuration files or scratchpads into upstream Git branches.

`ai-workspace` solves both problems through four pillars:

1. **Zero-Footprint Out-of-Tree Storage:** All AI knowledge files live outside your codebase in `~/.ai_workspaces/<project_name>/` (tracked by its own independent Git repository). Symlinks (`.ai`, `AGENTS.md`) expose the knowledge locally while `.git/info/exclude` keeps `git status` 100% clean.
2. **3-Tier Hierarchical Routing:**
   - **Tier 1 (`.ai/index.md`):** Global routing table mapping subsystems and key symbols to domain files (~40 tokens).
   - **Tier 2 (`.ai/domains/<domain>.md`):** Verified execution flows, data structures, ownership rules, and symbol coordinates (~1,000 tokens).
   - **Tier 3 (`ai-workspace slice`):** Surgical extraction of exact function or struct definitions without reading surrounding unrelated lines.
3. **Evidence-Driven State Machine:** Every claim and domain is tagged with its verification level (`[SKELETON]`, `[STATIC]`, `[VERIFIED]`, or `[NEEDS_REVERIFY]`).
4. **Closed-Loop Self-Healing:** Git hooks (`pre-commit`, `post-merge`) automatically detect modified functions, heal shifted line coordinates in unchanged functions, and flag only affected execution flows as `[NEEDS_REVERIFY]`.

---

## 2. System Requirements & Installation

### 2.1 Dependencies
- **Required:** `bash` (>= 4.0), `git`, standard POSIX utilities (`awk`, `sed`, `grep`, `find`, `sort`).
- **Recommended (for maximum speed & accuracy):**
  - `ripgrep` (`rg`): Accelerates file discovery and batch regex extraction by 10x–50x.
  - `Universal Ctags` (`ctags`): Provides AST-level C/C++ symbol and struct extraction (falls back automatically to high-speed batch `rg`/`awk` parser if absent).

### 2.2 First-Time Setup
Clone the `ai-workspace` repository to your machine. Running `init` or `migrate` on any project automatically links:
- The global CLI binary to `~/.local/bin/ai-workspace`
- The global `codebase-memory` skill to `~/.agents/skills/codebase-memory`

Ensure `~/.local/bin` is in your shell `PATH`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## 3. Quickstart: Setting Up a New Project

```bash
# 1. Preview workspace provisioning (no files modified)
/path/to/aiws/ai-workspace init --dry-run /path/to/your_project

# 2. Provision the out-of-tree workspace
/path/to/aiws/ai-workspace init /path/to/your_project

# 3. Navigate into your project
cd /path/to/your_project

# 4. Bootstrap your first domain module
./.ai/ai-workspace bootstrap net/driver drivers/net/ethernet/core/

# 5. View workspace status and copy the suggested next prompt for your AI agent
./.ai/ai-workspace status
```

---

## 4. Migrating an Existing Legacy Workspace

If you previously initialized an older version of `ai-workspace` on a codebase, upgrade it in place using a single command:

```bash
# Preview migration actions
./ai-workspace migrate --dry-run /path/to/existing_project

# Execute in-place migration
./ai-workspace migrate /path/to/existing_project
```

**What `migrate` does automatically:**
1. Commits and preserves any uncommitted WIP changes in `~/.ai_workspaces/<project_name>/`.
2. Normalizes legacy `**Status:**` headers in domain files to `**Overall Status:**`.
3. Cleans up obsolete duplicate directories/files from early versions (`.ai/docs`, `.ai/hooks`, `.ai/README.md`, `.ai/_template.md`).
4. Upgrades `AGENTS.md`, `_template.md`, `.ai/ai-workspace`, `.ai/lib/*.sh`, `.ai/scripts/*.sh`, global skills, and Git hooks (preserving custom hook logic).
5. Runs `reindex` and `refresh-coords` to heal drifted line numbers across all existing domains.

---

## 5. Complete CLI Command Reference

```text
ai-workspace [OPTIONS] <COMMAND> [ARGUMENTS...]
```

**Global Options:**
- `-d, --dry-run`: Preview all operations without modifying files or Git repositories.
- `-h, --help`: Display general or subcommand-specific usage instructions.

---

### 5.1 `init` — Provision Workspace
Provisions the out-of-tree AI workspace for a target repository.

```bash
ai-workspace init [OPTIONS] [target_codebase_directory]
```
- **Behavior:**
  - Creates `~/.ai_workspaces/<project_name>/` and initializes an isolated Git repository.
  - Deploys `index.md`, `conventions.md`, `lessons_learned.md`, `domains/_template.md`, and `AGENTS.md` (if not already present).
  - Links `.ai` and `AGENTS.md` into the target codebase and adds them to `.git/info/exclude`.
  - Supports standard Git repositories, **Git worktrees**, **submodules**, and **`repo`** workspaces via `git rev-parse --git-common-dir`.
  - Appends `ai-workspace` triggers idempotently into `pre-commit` and `post-merge` hooks without overwriting existing team hooks.

---

### 5.2 `migrate` — Upgrade Existing Workspace
Upgrades an existing out-of-tree workspace to the latest engine and schema without losing domain knowledge.

```bash
ai-workspace migrate [OPTIONS] [target_codebase_directory]
```

---

### 5.3 `bootstrap` — Extract Symbols & Create Domain Skeleton
Scans specified source directories or files, extracts language-specific symbols, generates `.ai/domains/<domain>.md`, and registers the domain in `.ai/index.md` with auto-discovered key symbols.

```bash
ai-workspace bootstrap [OPTIONS] <domain_name> <path_1> [path_2 ...]
```

**Examples:**
```bash
# C/C++ Subsystem (from repo root or any subdirectory)
ai-workspace bootstrap net/ipv6 src/net/ipv6/ include/net/ipv6.h

# Python Pytest Suite
ai-workspace bootstrap tests/qos tests/suites/qos/

# Shell Build & CI Scripts
ai-workspace bootstrap ci/image_build scripts/build/
```

**Extracted Artifacts by Language:**
| Language | Data Structures & State | Public APIs & Tests | Internal / Helpers | Callbacks, Fixtures & Traps |
| :--- | :--- | :--- | :--- | :--- |
| **C / C++** | `struct`, `typedef` | Non-static functions | `static` functions (excludes trivial header `inline`s) | Function pointers `(*cb)()` |
| **Python** | `class` definitions | `def` functions & `test_*` cases | Private `def _*()` | `@decorators` & `@pytest.fixture` |
| **Shell** | `export` & `declare` globals | Shell functions | Helper `_*()` functions | `trap` signal handlers |

*Note:* To prevent context bloat, `bootstrap` caps internal/static functions at `MAX_STATIC_SYMBOLS` (default: `80`) and outputs a ready-to-use prompt suggestion upon completion.

---

### 5.4 `slice` — Surgical Source Code Extraction
Extracts the exact implementation block of a function, struct, or class with line numbers—eliminating the need for AI agents to guess line ranges or read entire files.

```bash
ai-workspace slice <symbol_name | file:line[-end] | file:symbol> [max_lines]
```

**Examples:**
```bash
# 1. Slice by symbol name (automatically resolves coordinate from .ai/domains/*.md or codebase)
ai-workspace slice net_rx_action

# 2. Slice by file and starting line (automatically stops at closing '}' or Python dedent)
ai-workspace slice src/net/core/dev.c:450

# 3. Slice an explicit line range
ai-workspace slice src/net/core/dev.c:450-495

# 4. Slice a specific symbol inside a known file with custom max line cap (default: 160)
ai-workspace slice src/net/core/dev.c:net_rx_action 250
```

---

### 5.5 `refresh-coords` — Auto-Heal Drifted Line Coordinates
When lines are added or removed near the top of a source file, line numbers for unchanged functions further down shift. `refresh-coords` rescans referenced source files and automatically updates all `` `symbol()` (`path/to/file:line`) `` coordinates across domain markdown files.

```bash
# Refresh all domains in the workspace
ai-workspace refresh-coords

# Refresh a single specific domain
ai-workspace refresh-coords net/driver

# Preview coordinate updates without writing files
ai-workspace refresh-coords --dry-run
```

---

### 5.6 `sync` — Precision Staleness Tracking
Triggered automatically by Git `pre-commit` (`--cached`) and `post-merge` (`ORIG_HEAD..HEAD`) hooks, or invoked manually.

```bash
# Check staged changes (used by pre-commit hook)
ai-workspace sync --cached

# Check a specific commit range (used by post-merge hook or manual audit)
ai-workspace sync HEAD~3..HEAD
```

**How Precision `sync` Works:**
1. **Self-Heals Symlinks:** Recreates `.ai` and `AGENTS.md` symlinks if they were removed by `git clean -fdX`.
2. **Eliminates Basename Collisions:** Matches modified files by full relative path (`src/mod_a/util.c`) or verifies the file belongs to the domain's `**Source paths:**` before matching—so modifying `mod_a/util.c` never falsely invalidates `mod_b`.
3. **Auto-Heals Drifted Coordinates:** Automatically updates shifted line numbers for unchanged functions in affected domains.
4. **Function-Level Invalidation:** Parses `git diff -U0` hunk headers to identify exact modified functions/structs (`modified symbols: ...`), marking only the affected execution flows as `[NEEDS_REVERIFY]` while keeping unrelated verified flows intact.
5. **Scoped Git Commit:** Commits only the updated domain files and `index.md` to the external AI Git repository without touching unrelated uncommitted WIP.

---

### 5.7 `reindex` — Reconcile Knowledge Routing Table
Synchronizes `.ai/index.md` with all physical `.ai/domains/**/*.md` files.

```bash
ai-workspace reindex [--dry-run]
```
- Reads `**Overall Status:**` (or legacy `**Status:**`) and warning banners from each domain file.
- Preserves `[VERIFIED]`, `[STATIC]`, `[NEEDS_REVERIFY]`, and `[SKELETON]` states while keeping custom keywords in `.ai/index.md` intact.
- Appends any newly created domain files missing from `.ai/index.md`.
- Warns about orphaned index rows whose markdown files no longer exist.

---

### 5.8 `status` — Inspect Health & Actionable Prompt Suggestions
Displays a formatted overview of all domains, their verification states, and context-aware next steps.

```bash
ai-workspace status
```

**Example Output:**
```text
[*] AI Workspace Status for: my_project
[*] External storage: /home/user/.ai_workspaces/my_project

Domain / Module                Status          Knowledge File
------------------------------ --------------- ------------------------------
conventions                    [ACTIVE]        .ai/conventions.md
net/driver                     [NEEDS_REVERIFY].ai/domains/net/driver.md
net/protocol                   [STATIC]        .ai/domains/net/protocol.md
net/daemon                     [SKELETON]      .ai/domains/net/daemon.md

Summary: 0 Verified | 1 Static | 1 Needs Reverify | 1 Skeleton | 1 Other

Suggested Next Steps & Prompts:
  [NEEDS_REVERIFY] net/driver (modified symbols: `net_ring_alloc`):
    Prompt: "Reverify [NEEDS_REVERIFY] claims in .ai/domains/net/driver.md against git diff, update execution flows, and restore status."
  [SKELETON] net/daemon:
    Prompt: "Complete knowledge for net/daemon in .ai/domains/net/daemon.md using './.ai/ai-workspace slice', trace core execution flows, and promote to [STATIC]."
```

---

## 6. Knowledge Base Structure & Lifecycle States

### 6.1 External Workspace Layout (`~/.ai_workspaces/<project_name>/`)
- `AGENTS.md`: System rules instructing AI agents to route through `.ai/index.md` first.
- `.ai/index.md`: Tier-1 routing table.
- `.ai/conventions.md`: Cross-cutting rules (memory ownership, locking hierarchies, IPC schemas).
- `.ai/lessons_learned.md`: Post-mortem runtime traps, hardware quirks, and concurrency anti-patterns.
- `.ai/domains/<domain>.md`: Tier-2 module call graphs, structs, callbacks, and symbol coordinates.

### 6.2 Canonical Coordinate Format
Always write symbol coordinates in domain files using backticks and parentheses:
- Functions: `` `func_name()` (`path/to/file.c:120`) ``
- Structs / Classes: `` `struct ctx_name` (`path/to/file.h:45`) `` or `` `class MyHandler` (`path/to/app.py:30`) ``

This exact format enables `ai-workspace refresh-coords` and `ai-workspace slice` to parse and auto-heal coordinates deterministically.

### 6.3 Verification Lifecycle States
| Marker | Meaning | Requirement to Assign |
| :--- | :--- | :--- |
| `[SKELETON]` | Auto-generated symbol list from `bootstrap`. | Default state after `bootstrap`. |
| `[STATIC]` | Traced and verified against source code syntax and call hierarchies. | Agent/engineer inspected implementation via `slice` or source read; not yet executed at runtime. |
| `[VERIFIED]` | Confirmed by actual runtime execution, test suite, or hardware trace. | Must record test command, environment, observed output, and git revision. |
| `[NEEDS_REVERIFY]` | Underlying source file/function was modified since last verification. | Assigned automatically by `sync`; cleared after reconciling claims against `git diff`. |

---

## 7. Working with AI Coding Agents (`codebase-memory` Skill)

When an AI agent (equipped with `AGENTS.md` and the `codebase-memory` skill) works in your repository, it automatically follows a 5-part workflow:

1. **Load Relevant Context:** Reads `.ai/index.md` first, selects the matching domain file, checks `.ai/conventions.md` and `.ai/lessons_learned.md`, and uses `./.ai/ai-workspace slice <symbol>` to inspect specific functions.
2. **Verify Claims Against Evidence:** Checks whether claims are `[STATIC]`, `[VERIFIED]`, or `[NEEDS_REVERIFY]` before trusting them. Never marks a flow as `[VERIFIED]` based solely on a clean build.
3. **Review Source Files, Commits, or Architecture Compliance:** Routes code reviews through domain invariants and conventions first (`references/architecture-review.md` for 5-axis SDK compliance audits), presenting prioritized findings (`path:line`) separately from proposed `.ai/` knowledge updates.
4. **Persist Reusable Findings:** Saves newly traced execution flows into `.ai/domains/<module>.md`, architectural rules into `.ai/conventions.md`, and runtime traps into `.ai/lessons_learned.md`.
5. **Contextual Next-Step Suggestions:** At the end of a task, if the agent had to explore an unindexed/`[SKELETON]` module, encountered `[NEEDS_REVERIFY]`, or diagnosed a runtime bug, it proactively suggests a 1-line next step to persist the knowledge.

---

## 8. High-Leverage Prompt Engineering Catalog

### Pattern 1: Promote a `[SKELETON]` Domain to `[STATIC]`
```text
Complete knowledge for `<domain>` in `.ai/domains/<domain>.md`.
Use `./.ai/ai-workspace slice <symbol>` to inspect key entry points and structs without broad scans.
Populate `## 1. Core Execution Flows` and `## 2. Data Structures & Memory Ownership` with exact `file:line` coordinates, update `**Overall Status:**` to `[STATIC]`, and run `./.ai/ai-workspace reindex`.
```

### Pattern 2: Reconcile a `[NEEDS_REVERIFY]` Domain After Code Changes
```text
Reverify `[NEEDS_REVERIFY]` claims in `.ai/domains/<domain>.md` against recent git diffs.
Run `./.ai/ai-workspace refresh-coords <domain>` first, inspect modified functions, update affected call graphs, remove the warning banner, and restore status to `[STATIC]` (or `[VERIFIED]`).
```

### Pattern 3: Fast Token-Economical Query
```text
Using `.ai/index.md` and the knowledge in `.ai/domains/<domain>.md`, explain how `<feature/mechanism>` works and which locks protect `<struct_name>`. Only slice source functions if a detail is missing from the domain file.
```

### Pattern 4: Code Review Against Project Conventions
```text
Review my staged changes (`git diff --cached`) using `codebase-memory`.
Cross-check against `.ai/conventions.md`, `.ai/lessons_learned.md`, and relevant domain files in `.ai/index.md` for locking violations, memory leaks, or broken invariants.
```

### Pattern 5: Record a Runtime Bug / Trap (`[VERIFIED]`)
```text
We confirmed at runtime (on revision `<commit_sha>` via `<test_command>`) that `<symptom>` was caused by `<root_cause>`.
Record this trap in `.ai/lessons_learned.md` and promote the corresponding flow in `.ai/domains/<domain>.md` from `[STATIC]` to `[VERIFIED]`.
```

### Pattern 6: Build SDK Architecture Baseline (From SDK Docs + Source)
```text
/codebase-memory Create SDK architecture knowledge for `arch/sdk_core` at `.ai/domains/arch/sdk_core.md` from <@sdk_arch_doc> and verify every API, header, locking rule, and IPC boundary against source using `bash ./.ai/ai-workspace slice`.
Cover all 5 review axes (Layering, Subsystem Ownership & Build Isolation, IPC/Lifecycle, Locking/Memory Ownership, State Source-of-Truth), set `**Overall Status:** [STATIC]`, and register broad routing keywords (`architecture, layering, IPC, locking, new app, review`) in `.ai/index.md`.
```
*Tip:* For large SDK PDFs, specify exact chapters or page ranges (Architecture Overview, IPC, Locking, Data Model) rather than feeding hundreds of pages at once; split monolithic vs. distributed architectures into separate `.ai/domains/arch/*.md` files when needed.

### Pattern 7: Audit an Application or Commit for Architecture Compliance
```text
/codebase-memory Perform an architecture compliance review of `src/apps/<new_app>/` (or commit `<commit_sha>`) against `.ai/domains/arch/sdk_core.md` and `.ai/conventions.md`.
Evaluate all 5 architectural axes (including build dependencies, lock boundaries around IPC/persistence, and state source-of-truth) and output a compliance verdict with `[ARCH]` and `[BUG]` findings.
```

---

## 9. Environment Variables & Customization

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `AI_WORKSPACE_DIR` | `~/.ai_workspaces/<project_name>` | Overrides the external storage directory path (useful when two repos share the same folder basename). |
| `TARGET_CODEBASE` | Current Git toplevel (`pwd`) | Overrides the target host repository path when invoking commands outside the repo tree. |
| `MAX_STATIC_SYMBOLS` | `80` | Maximum number of internal/static helper functions included in `## 4. Symbol Coordinates` during `bootstrap` (`0` = unlimited). |
| `DRY_RUN` | `false` | Set to `true` (or pass `-d` / `--dry-run`) to preview any command without modifying disk state. |

---

## 10. Troubleshooting & FAQ

**Q1: `git clean -fdX` deleted `.ai` and `AGENTS.md` in my repository. Did I lose my knowledge base?**  
**A:** No. All data lives safely in `~/.ai_workspaces/<project_name>/`. The next time `git commit` / `git merge` triggers `ai-workspace sync`, or when you run `ai-workspace bootstrap` / `ai-workspace init`, the `.ai` and `AGENTS.md` symlinks are automatically recreated.

**Q2: My project already has custom `.git/hooks/pre-commit` scripts (e.g., linters or Gerrit hooks). Will `init` or `migrate` overwrite them?**  
**A:** No. `ai-workspace` detects existing hook files and idempotently appends the `sync_ai_kb.sh` trigger block at the end of the file, preserving all existing hook commands.

**Q3: Does `ai-workspace` work with Git Worktrees, Submodules, or Google `repo`?**  
**A:** Yes. `ai-workspace` uses `git rev-parse --is-inside-work-tree` and `git rev-parse --path-format=absolute --git-common-dir` to locate the shared Git metadata directory even when `.git` is a pointer file.

**Q4: What happens if I edit source files and line numbers shift by 50 lines?**  
**A:** Both `ai-workspace sync` (run automatically on commit/merge) and `ai-workspace refresh-coords` automatically rescan symbol definitions and update `` (`path/to/file:line`) `` coordinates in place.

**Q5: How do I inspect the version history of my AI knowledge base?**  
**A:** Since the external workspace is a standalone Git repository, run standard Git commands against it:
```bash
git -C ~/.ai_workspaces/<project_name> log --stat -n 10
git -C ~/.ai_workspaces/<project_name> diff HEAD~1
```
