# AI Workspace (`ai-workspace`)

A zero-footprint, out-of-tree AI workspace and self-evolving knowledge base tooling framework for multi-language codebases (C/C++, Python, Shell, and more).

> **Documentation:**
> - [Comprehensive User Guide (`docs/user_guide.md`)](docs/user_guide.md) — Complete CLI reference, workflows, prompt catalog, and troubleshooting.
> - [Mastering `/codebase-memory` Skill Guide (`docs/codebase_memory_skill_guide.md`)](docs/codebase_memory_skill_guide.md) — Practical playbook for using the `/codebase-memory` agent skill effectively.
> - [Integration & Rollout Plan (`docs/ai_workspace_integration_plan.md`)](docs/ai_workspace_integration_plan.md) — 5-phase production rollout guide.
> - [System Architecture Specification (`docs/self_evolving_knowledge_base_architecture.md`)](docs/self_evolving_knowledge_base_architecture.md) — Deep-dive architectural design.

---

## 1. Overview

In massive repositories (monolithic firmware, operating system kernels, large networking SDKs, extensive Python test automation frameworks, and CI/CD shell infrastructure), naive AI agent searches (e.g., broad `grep` across thousands of files) cause excessive token consumption, latency, and hallucinations. Moreover, strict enterprise git policies often forbid committing AI scratchpads, prompt files, or generated domain metadata directly into upstream branches.

`ai-workspace` resolves these challenges through an **Out-of-Tree Architecture**:
- **Zero Footprint in Upstream Git:** Stores all knowledge documents, agent skills, and rules outside the source tree in `~/.ai_workspaces/<project_name>/`.
- **Transparent Local Access:** Bridges assets into the local repository via symlinks (`.ai`, `.agent`, `AGENTS.md`) and hides them entirely from Git using `.git/info/exclude`.
- **2-Tier Lazy Context Loading & Surgical Slicing:** Equips AI agents with a fast routing index (`.ai/index.md`) that maps modules and top symbols to domain files (`.ai/domains/<domain>.md`), plus `ai-workspace slice` to extract exact function/struct blocks, saving 95%+ of context tokens.
- **Function-Level Staleness Tracking & Auto Drift Healing:** Uses Git hooks (`pre-commit`, `post-merge`) to detect changes in tracked source files (`*.c`, `*.h`, `*.cpp`, `*.py`, `*.sh`, etc.), automatically heals shifted line coordinates for unchanged functions, and flags modified execution flows with `[NEEDS_REVERIFY]`.
- **Dual-Repository Isolation:** Tracks knowledge evolution and agent learning in an independent, local Git repository.
- **Polyglot & Multi-Language Support:** First-class symbol extraction and call graph tracing across C/C++, Python (including Pytest test suites and fixtures), and Shell scripts.

---

## 2. Architecture

```
┌────────────────────────────────────────────────────────┐
│               Host Codebase Repository                 │
│  - Source Files (*.c, *.h, *.py, *.sh, *.cpp)          │
│  - .git/info/exclude  ──> Ignores .ai, .agent, AGENTS   │
│  - .git/hooks/        ──> pre-commit, post-merge       │
│  - .ai/               ──> Symlink to external storage  │
│  - .agent/            ──> Symlink to external skills   │
│  - AGENTS.md          ──> Symlink to external rules    │
└───────────────────────────┬────────────────────────────┘
                            │ Points to
┌───────────────────────────▼────────────────────────────┐
│   External AI Storage: ~/.ai_workspaces/<project_name> │
│  - .git/              ──> Independent Version Control  │
│  - .ai/index.md       ──> Tier-1 Routing Table         │
│  - .ai/conventions.md ──> Cross-Cutting Conventions    │
│  - .ai/domains/*.md   ──> Tier-2 Domain Call Graphs    │
│  - .ai/ai-workspace   ──> Master CLI Executable        │
│  - .agent/skills/     ──> codebase-memory Skill        │
└────────────────────────────────────────────────────────┘
```

---

## 3. Directory Structure

```
ai_workspace_project/
├── ai-workspace                  # Master Unified Deep CLI Module
├── install_ai_workspace.sh       # Backward-compatible wrapper -> ai-workspace init
├── lib/
│   ├── common.sh                 # Environment resolution, logging, error traps
│   ├── symbol_extractor.sh       # Internal Seam: Ctags & regex symbol engine
│   ├── knowledge_registry.sh     # Internal Seam: Domain state machine & staleness engine
│   └── workspace_provisioner.sh  # Internal Seam: Dual-repo initialization & symlinks
├── scripts/
│   ├── bootstrap_domain.sh       # Backward-compatible wrapper -> ai-workspace bootstrap
│   └── sync_ai_kb.sh             # Backward-compatible wrapper -> ai-workspace sync
├── templates/
│   ├── _template.md              # Gold-standard template for domain knowledge
│   ├── conventions.md            # Cross-cutting architectural & locking conventions
│   ├── index.md                  # Tier-1 routing table template
│   ├── lessons_learned.md        # Runtime lessons & anti-patterns template
│   └── hooks/
│       ├── pre-commit            # Git hook detecting staged changes
│       └── post-merge            # Git hook detecting merged changes
├── skills/
│   └── codebase-memory/
│       └── SKILL.md              # 3-Phase Agent Memory & Verification Skill
└── AGENTS.md                     # System instructions for AI coding agents
```

---

## 4. Installation & Quickstart

### 4.1 Initialize Workspace for Target Codebase

You can initialize the workspace from any directory by passing the target repository path:

```bash
# Direct invocation
./ai-workspace init /path/to/target_repository

# Or using the backward-compatible installer script
./install_ai_workspace.sh /path/to/target_repository
```

**Options:**
- `-d, --dry-run`: Preview all operations without modifying files or directories.
- `AI_WORKSPACE_DIR`: Override external storage path (default: `~/.ai_workspaces/<project_name>`).

---

## 5. Usage Workflow

### Step 1: Bootstrap a Domain or Sub-Domain
Extract symbols, data structures, public functions, test cases, and callbacks/fixtures from target source trees:

```bash
cd /path/to/target_repository

# 1. C/C++ Systems & Subsystems:
./.ai/ai-workspace bootstrap network_core src/network/
./.ai/ai-workspace bootstrap net/driver drivers/net/ethernet/core/

# 2. Python Automation Test Frameworks & Suites:
./.ai/ai-workspace bootstrap tests/api_suite tests/suites/api/
./.ai/ai-workspace bootstrap test_framework tests/framework/

# 3. Shell Script & CI/CD Infrastructure:
./.ai/ai-workspace bootstrap ci/provisioning scripts/ci/
```

*Backward-compatible wrapper also supported:*
```bash
./.ai/scripts/bootstrap_domain.sh net/driver drivers/net/ethernet/core/
```

### Step 2: Check Workspace Status
Display a summary table of all registered domains, verification statuses, and file locations:

```bash
./.ai/ai-workspace status
```

Example output:
```text
[*] AI Workspace Status for: my_project
[*] External storage: /home/user/.ai_workspaces/my_project

Domain / Module                Status          Knowledge File
------------------------------ --------------- ------------------------------
conventions                    [ACTIVE]        .ai/conventions.md
net/driver                     [VERIFIED]      .ai/domains/net/driver.md
net/protocol                   [SKELETON]      .ai/domains/net/protocol.md

Summary: 1 Verified | 0 Static | 0 Needs Reverify | 1 Skeleton | 1 Other
```

### Step 2.5: Surgical Source Slicing & Auto Coordinate Refresh
Extract an exact function or struct definition block (by symbol name or `file:line`) without loading the entire file, or auto-heal shifted line numbers after edits:

```bash
# Extract exact function or struct body (tracks brace depth / Python indentation automatically)
./.ai/ai-workspace slice net_rx_action
./.ai/ai-workspace slice drivers/net/ethernet/core/net_ring.c:120

# Auto-heal drifted symbol line numbers across domain files
./.ai/ai-workspace refresh-coords
```

### Step 3: Automated Staleness Tracking
When code is committed or merged in the host repository, installed Git hooks automatically execute:

```bash
./.ai/ai-workspace sync --cached
```

- If source files referenced in a domain are modified, the entry is automatically tagged with `[NEEDS_REVERIFY]`.
- A warning banner (`> [!WARNING] [NEEDS_REVERIFY]`) is injected into the domain document.
- Changes are committed to the external Git repository without touching upstream Git status.

### Step 4: Reconcile & Synchronize Knowledge Index (reindex)
If domain files are added, removed, or their statuses are updated directly by AI agents or developers, reconcile `.ai/index.md` at any time:

```bash
./.ai/ai-workspace reindex
```

- Scans all `.ai/domains/**/*.md` files.
- Automatically synchronizes domain statuses (`[VERIFIED]`, `[NEEDS_REVERIFY]`, `[SKELETON]`) with `.ai/index.md` while preserving customized keywords.
- Discovers and registers any new domain files missing from the index.
- Identifies and warns about any orphaned entries.

### Step 5: Interacting with AI Coding Agents
AI coding agents equipped with the `codebase-memory` skill follow a 3-Phase protocol:
1. **Lazy Context Loading:** Agent reads `.ai/index.md` first, loading only the specific domain markdown file needed.
2. **Verification:** Agent checks verification state (`[VERIFIED]`, `[STATIC]`, `[NEEDS_REVERIFY]`) against git diffs.
3. **Self-Evolving Persistence:** Agent updates call graphs, structs, and traps back into `.ai/domains/<domain>.md` and `.ai/conventions.md`.

---

## 6. Prompt Engineering Guide & Usage Examples

To maximize token economy, eliminate hallucinations, and trigger self-evolving knowledge persistence, prompts should follow a structured anatomy aligned with the `codebase-memory` protocol.

### 6.1 Standard Prompt Anatomy

Every high-leverage prompt should contain four distinct components:

```
┌────────────────────────────────────────────────────────┐
│ [1. CONTEXT / SCOPE]                                   │
│ Target domain or sub-domain (e.g., `net/driver`, `core`)│
├────────────────────────────────────────────────────────┤
│ [2. GOAL / INTENT]                                     │
│ Specific question, execution flow trace, or bugfix     │
├────────────────────────────────────────────────────────┤
│ [3. CONSTRAINTS & REFERENCES]                          │
│ Mandate reading .ai/index.md; forbid broad grep/find   │
├────────────────────────────────────────────────────────┤
│ [4. PERSISTENCE INSTRUCTION]                           │
│ Explicit instruction to update .ai/domains/<module>.md │
│ and transition status to [VERIFIED]                    │
└────────────────────────────────────────────────────────┘
```

#### Standard Prompt Template:
```text
In subsystem `<DOMAIN_NAME>`, analyze `<FEATURE_OR_FLOW>`.
Refer to `.ai/domains/<DOMAIN_NAME>.md` and its referenced source paths. Do not perform wide codebase scans.
Trace the exact call hierarchy with `file:line` coordinates, explaining memory ownership and state transitions.
Finally, update `## 1. Core Execution Flows` in `.ai/domains/<DOMAIN_NAME>.md` with this verified summary and transition its status to `[VERIFIED]`.
```

---

### 6.2 Catalog of High-Leverage Prompt Patterns

#### Pattern 1: Deep Execution Flow Analysis & Knowledge Capture
- **Purpose:** Analyze a complex mechanism (e.g., ring buffer initialization, packet TX/RX path, DMA setup) and permanently record verified call graphs.
- **Prompt:**
  ```text
  Analyze the ring buffer allocation and DMA initialization flow in module `net/driver`. 
  Trace the call graph starting from driver initialization down to hardware ring allocation, noting physical address mappings and memory types. 
  After explaining the mechanism, update the call hierarchy into `## 1. Core Execution Flows` of `.ai/domains/net/driver.md` and mark the overall status as `[VERIFIED]`.
  ```
- **Outcome:** The agent avoids scanning irrelevant modules, analyzes only target files, and commits verified findings into the external Git repository.

#### Pattern 2: Rapid Knowledge Re-use (Token Economy Query)
- **Purpose:** Retrieve verified insights in seconds without re-reading thousands of lines of C code.
- **Prompt:**
  ```text
  Based strictly on the verified knowledge recorded in `.ai/domains/net/driver.md`, explain how dynamic queue IDs are allocated and mapped to hardware TX/RX rings. 
  Specify the exact function coordinates and data structures involved. Do not re-scan the underlying C source files.
  ```
- **Outcome:** Instant response using <1,000 tokens instead of 50,000+ tokens.

#### Pattern 3: Synthesizing Cross-Cutting Conventions
- **Purpose:** Extract and consolidate memory allocation, locking, or API usage conventions into `.ai/conventions.md`.
- **Prompt:**
  ```text
  Review the locking hierarchy and memory allocation rules in module `net/driver`. 
  Identify the rules governing spinlock acquisition in interrupt/tasklet context versus process context, and buffer ownership on error returns. 
  Consolidate these engineering rules and append them to `.ai/conventions.md`.
  ```
- **Outcome:** Centralizes critical rules so future agents and developers do not introduce subtle concurrency bugs.

#### Pattern 4: Code Review against Established Conventions
- **Purpose:** Verify newly written code or proposed patches against `.ai/conventions.md`.
- **Prompt:**
  ```text
  I want to introduce the following packet processing routine inside the driver tasklet handler:
  [INSERT CODE SNIPPET / DIFF]
  Review this implementation strictly against the concurrency and memory rules documented in `.ai/conventions.md`. 
  Flag any violations such as sleeping in atomic context, improper memory allocation flags, or lock ordering inversions.
  ```
- **Outcome:** Catches critical architectural violations before code reaches hardware or CI.

#### Pattern 5: Invalidation Reconciliation (`[NEEDS_REVERIFY]`)
- **Purpose:** Refresh domain knowledge after Git hooks flag source modifications.
- **Prompt:**
  ```text
  The domain `.ai/domains/net/driver.md` has been marked as `[NEEDS_REVERIFY]` due to recent git commits. 
  Inspect the git diff of the modified source files, reconcile any altered function prototypes or line numbers in the call graph, 
  and update `.ai/domains/net/driver.md` back to `[VERIFIED]`.
  ```
- **Outcome:** Keeps documentation accurate across active development cycles without manual auditing.

#### Pattern 6: Root Cause Diagnosis & Runtime Trap Recording
- **Purpose:** Debug complex runtime issues and capture non-obvious traps to prevent future regressions.
- **Prompt:**
  ```text
  Diagnose the root cause of `<SYMPTOM / KERNEL_PANIC_LOG>` in subsystem `<DOMAIN_NAME>`. 
  Trace the execution path that triggers the failure, explain why static analysis might overlook this edge case, 
  and propose a fix. Once resolved, record the trap and underlying invariant into `.ai/lessons_learned.md`.
  ```
- **Outcome:** The agent documents the runtime trap, ensuring subsequent sessions immediately recognize the anti-pattern.

---

## 7. Multi-Language & Polyglot Codebase Support

The framework natively recognizes and extracts symbols across multiple programming paradigms without requiring external language runtimes:

| Language / Domain | Target Files | Extracted Data Structures & State | Extracted APIs & Functions | Extracted Callbacks, Fixtures & Traps |
| :--- | :--- | :--- | :--- | :--- |
| **C / C++** | `*.c`, `*.h`, `*.cpp`, `*.hpp` | `struct`, `union`, `typedef` | Public and `static` functions | Function pointer callbacks (`(*cb)()`) |
| **Python** (e.g., Automation & Pytest) | `*.py` | `class <Name>`, dataclasses | `def` public APIs, `test_*` cases, private `_*` | `@pytest.fixture`, decorators, test hooks |
| **Shell Script** (e.g., CI/CD & Harnesses) | `*.sh`, `*.bash` | `export` & `declare` globals | Public functions and helper `_*` | `trap` signal handlers, lifecycle hooks |

### Automated Staleness Tracking Across Languages
When Git detects changes across any tracked extension (`.c`, `.h`, `.cpp`, `.py`, `.sh`, `.bash`), `ai-workspace sync` automatically marks the affected domain with `[NEEDS_REVERIFY]`, ensuring agents never execute test suites or modify drivers against outdated assumptions.

---

## 8. Defensive Engineering Standards

All scripts adhere to strict Bash defensive patterns:
- **Strict Mode:** `set -Eeuo pipefail` with explicit `trap ERR` reporting line numbers and failing commands.
- **Safe Temp Directory:** Uses a single `mktemp -d` cleaned up via `trap EXIT`.
- **Heredoc-Free:** All templates live in standalone files; CLI usage and documents are rendered through builtin `printf` streams.
- **Symlink Preservation:** Uses `sed --follow-symlinks` to ensure symlinks are never broken into regular files.
- **Safe Command Substitution:** Diagnostic logging is routed to `stderr`, keeping `stdout` purely for data streams.
