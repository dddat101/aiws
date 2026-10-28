# Mastering the `/codebase-memory` Skill — Practical Guide for Engineers

**Skill Identifier:** `/codebase-memory`  
**Location:** `skills/codebase-memory/SKILL.md` (linked globally to `~/.agents/skills/codebase-memory`)  
**Purpose:** Maximize AI accuracy, cut token consumption by 90%+, and build a self-evolving engineering knowledge base across daily coding, debugging, and code review tasks.

---

## Table of Contents
1. [How `/codebase-memory` Works Under the Hood](#1-how-codebase-memory-works-under-the-hood)
2. [Implicit vs. Explicit Activation: When to Type `/codebase-memory`](#2-implicit-vs-explicit-activation-when-to-type-codebase-memory)
3. [The 5 Core Workflows & Copy-Paste Prompt Playbook](#3-the-5-core-workflows--copy-paste-prompt-playbook)
   - [Workflow A: Bootstrapping & Building Knowledge for a New Feature](#workflow-a-bootstrapping--building-knowledge-for-a-new-feature)
   - [Workflow B: Fast Architectural Q&A & Call-Graph Tracing](#workflow-b-fast-architectural-qa--call-graph-tracing)
   - [Workflow C: Root-Cause Debugging & Capturing Runtime Traps](#workflow-c-root-cause-debugging--capturing-runtime-traps)
   - [Workflow D: High-Signal Code Review (Staged Diffs, Commits, PRs)](#workflow-d-high-signal-code-review-staged-diffs-commits-prs)
   - [Workflow E: Reconciling `[NEEDS_REVERIFY]` After Code Changes](#workflow-e-reconciling-needs_reverify-after-code-changes)
   - [Workflow F: SDK Architecture Knowledge & Compliance Review](#workflow-f-sdk-architecture-knowledge--compliance-review)
4. [Understanding & Managing Evidence Levels](#4-understanding--managing-evidence-levels)
5. [Best Practices for Maximum Token Economy & Speed](#5-best-practices-for-maximum-token-economy--speed)
6. [Anti-Patterns to Avoid](#6-anti-patterns-to-avoid)
7. [Quick Cheat Sheet](#7-quick-cheat-sheet)

---

## 1. How `/codebase-memory` Works Under the Hood

Without `/codebase-memory`, an AI agent treats every prompt as a cold start—running broad `rg`/`grep` searches, reading thousands of lines of irrelevant files, and forgetting everything once the session ends.

With `/codebase-memory`, the agent operates as a **stateful senior engineer** using a 3-tier retrieval and persistence loop:

```text
User Prompt
    │
    ▼
[Tier 1: .ai/index.md] ──> Matches feature/symptom to specific domain (~40 tokens)
    │
    ▼
[Tier 2: .ai/domains/<module>.md] ──> Loads verified call graphs, structs & traps (~1,000 tokens)
    │                                 (+ .ai/conventions.md & .ai/lessons_learned.md)
    ▼
[Tier 3: ai-workspace slice <sym>] ──> Extracts exact function/struct block (~50-150 lines)
    │
    ▼
[Self-Evolving Persistence] ──> Updates coordinates, call graphs, or lessons learned
```

---

## 2. Implicit vs. Explicit Activation: When to Type `/codebase-memory`

Because `AGENTS.md` in your repository mandates checking `.ai/index.md` first, the agent will consult `.ai/` automatically on most questions. However, **explicitly prefixing your prompt with `/codebase-memory` unlocks specialized permissions and workflows**:

| How You Prompt | What the Agent Is Authorized to Do | Best Used For |
| :--- | :--- | :--- |
| **Normal prompt** (no slash prefix) | Reads `.ai/index.md` and domain files to answer your question or write code. Asks before modifying `.ai/` during code reviews. | Everyday coding, quick questions, bug fixes. |
| **`/codebase-memory <instruction>`** | **Pre-authorizes** autonomous domain bootstrapping (`ai-workspace bootstrap`), coordinate healing (`refresh-coords`), surgical slicing (`slice`), and direct `.ai/` persistence without stopping to ask for confirmation. | Creating new domain docs, refreshing stale knowledge, deep module onboarding, and convention audits. |

---

## 3. The 5 Core Workflows & Copy-Paste Prompt Playbook

### Workflow A: Bootstrapping & Building Knowledge for a New Feature
Use this when starting work on an unfamiliar subsystem or feature that does not yet have a `[STATIC]` or `[VERIFIED]` domain file.

- **What you need to provide:** Just the feature name or symptom. You do **not** even need to know the exact directory paths—the skill instructs the agent to discover the implementing paths, run `bootstrap`, slice the key functions, and replace the `[SKELETON]` placeholders with real call graphs.
- **Prompts to use:**
  ```text
  /codebase-memory Add knowledge for packet QoS classification and queue scheduling
  ```
  *Or if you already know the target domain and path:*
  ```text
  /codebase-memory Bootstrap domain `net/qos` from `src/net/qos/` and complete its core execution flows and struct ownership at `[STATIC]` level.
  ```
- **What happens behind the scenes:**
  1. Agent checks `.ai/index.md` to avoid duplicates.
  2. Runs `./.ai/ai-workspace bootstrap <domain> <paths>` to extract symbols and auto-populate `.ai/index.md` keywords.
  3. Uses `./.ai/ai-workspace slice <symbol>` on key entry points to trace the call hierarchy.
  4. Rewrites `.ai/domains/<domain>.md` with traced flows, sets `**Overall Status:** [STATIC]`, and runs `reindex`.

---

### Workflow B: Fast Architectural Q&A & Call-Graph Tracing
Use this when you want an instant, accurate explanation of how a subsystem works without waiting for the agent to scan the repository.

- **Prompts to use:**
  ```text
  /codebase-memory Trace the initialization and message dispatch flow in `ssk`. Show exact `file:line` coordinates and locking rules.
  ```
  ```text
  /codebase-memory How does `net/driver` handle DMA ring allocation failures? Base your answer on `.ai/domains/net/driver.md` and slice only the error-handling functions if needed.
  ```
- **Pro Tip:** If the agent discovers a secondary flow that wasn't documented yet, it will offer a 1-line suggestion at the end of its reply asking if you want to save the newly traced flow into `.ai/domains/<module>.md`. Simply reply `"Yes"` to persist it.

---

### Workflow C: Root-Cause Debugging & Capturing Runtime Traps
Static code reading often misses runtime behavior (e.g., function pointers overridden at init, timer race conditions, or hardware register quirks). Use `/codebase-memory` both to **check known traps first** and to **record new traps after fixing a bug**.

- **Step 1 — Diagnose with existing memory:**
  ```text
  /codebase-memory We are seeing a deadlock when reconfiguring the interface under heavy traffic:
  [PASTE LOG / STACK TRACE]
  Check `.ai/lessons_learned.md`, `.ai/conventions.md`, and the matching domain in `.ai/index.md` to identify the root cause.
  ```
- **Step 2 — Persist the fix and promote to `[VERIFIED]`:**
  Once you test the fix on hardware or in your test suite, lock in that institutional knowledge:
  ```text
  /codebase-memory We verified on commit `a1b2c3d` (by running `pytest tests/suites/stress_reconfig.py`) that the deadlock was caused by acquiring `cfg_mutex` inside the timer callback.
  Record this trap in `.ai/lessons_learned.md` and promote the reconfiguration flow in `.ai/domains/net/driver.md` to `[VERIFIED]`.
  ```

---

### Workflow D: High-Signal Code Review (Staged Diffs, Commits, PRs)
Instead of generic style nitpicks, `/codebase-memory` reviews your code against **project-specific memory ownership rules, lock ordering hierarchies, and domain invariants**.

- **Prompts to use:**
  ```text
  /codebase-memory Review my staged changes (`git diff --cached`).
  ```
  ```text
  /codebase-memory Review commit `HEAD` (or range `main..HEAD`) for regressions, concurrency hazards, and memory leaks.
  ```
- **What you get:**
  1. **Prioritized Findings First:** Ordered by severity (`path:line`, triggering condition, impact, and proof from source/conventions).
  2. **Separate Knowledge Update Proposals:** At the bottom of the review, the agent lists any `.ai/domains/*.md` coordinates or flows that will need updating once your patch lands—without modifying `.ai/` behind your back during a review.

---

### Workflow E: Reconciling `[NEEDS_REVERIFY]` After Code Changes
When you commit or pull code, Git hooks automatically run `ai-workspace sync`. Unchanged functions have their shifted line numbers healed automatically, while modified functions cause their domain to be flagged as `[NEEDS_REVERIFY]`.

1. **Check which domains need attention:**
   ```bash
   ./.ai/ai-workspace status
   ```
   The CLI prints ready-to-use prompts under `Suggested Next Steps & Prompts:`.
2. **Copy-paste the suggested prompt (or run):**
   ```text
   /codebase-memory Reverify `[NEEDS_REVERIFY]` claims in `.ai/domains/net/driver.md` against git diff, update execution flows, and restore status.
   ```

---

### Workflow F: SDK Architecture Knowledge & Compliance Review
Use `/codebase-memory` (backed by `skills/codebase-memory/references/architecture-review.md`) to turn SDK architecture specifications into an actionable compliance baseline, then audit commits or entire new applications against it.

- **Step 1 — Build the SDK Architecture Baseline (Combining SDK Docs + Source Verification):**
  If you have official SDK architecture docs, `@mention` them in your prompt and instruct the agent to verify every claim against actual code so the knowledge reflects real implementation:
  ```text
  /codebase-memory Create SDK architecture knowledge for `arch/sdk_core` at `.ai/domains/arch/sdk_core.md` by combining <@sdk_architecture_doc> with source verification in this repository.

  Structure the domain around the 5 architecture-review axes with explicit Allowed vs. Forbidden patterns:
  1. Layering & Dependency Direction (e.g., App/CLI -> Public Facade/DAL -> Data Model/Core -> OS/Kernel).
  2. Subsystem Ownership & Build-Mode Isolation (e.g., monolithic vs. distributed/modular daemon boundaries and compile-time guards).
  3. IPC, Process Lifecycle & Entity Registration (service supervisor registration, message bus ownership, startup readiness).
  4. Locking & Memory Ownership (shared model lock boundaries, rules forbidding blocking IPC or flash persistence while holding locks).
  5. State Source-of-Truth & Persistence (authoritative config manager vs. shadow files/direct store writes; read-only getter purity).

  Verify every API, header path, and lifecycle rule from <@sdk_architecture_doc> using `bash ./.ai/ai-workspace slice`, format symbols as `` `symbol()` (`path:line`) ``, set `**Overall Status:** [STATIC]`, and register `arch/sdk_core` in `.ai/index.md` with broad routing keywords (`architecture, layering, IPC, locking, data model, new app, review`).
  ```
  - **Tips for Large SDK Docs & Splitting:**
    - **Avoid context overflow:** If the SDK document is a multi-hundred-page PDF, extract the relevant table of contents or specify exact chapters/pages (Architecture Overview, IPC/Messaging, Locking, Data Model) in your prompt instead of passing the entire raw dump.
    - **Split massive architectures:** When monolithic and distributed SDK modes are both large, split them into `.ai/domains/arch/classic_sdk.md` and `.ai/domains/arch/distributed_sdk.md` to keep Tier-2 context loads compact.
- **Step 2 — Audit a Commit or New Application for Compliance:**
  ```text
  /codebase-memory Perform an architecture compliance review of `src/apps/<new_app>/` (or commit `<commit_sha>`) against `.ai/domains/arch/sdk_core.md` and `.ai/conventions.md`.
  Audit all 5 architectural axes (including build files/dependencies, locking around IPC/persistence, and state source-of-truth) and classify `[ARCH]` vs `[BUG]` findings.
  ```

---

## 4. Understanding & Managing Evidence Levels

`/codebase-memory` strictly separates **what the code looks like statically** from **what has been proven at runtime**. Never let an agent blur these states:

| Status Marker | What It Means | How to Transition Out of It |
| :--- | :--- | :--- |
| **`[SKELETON]`** | Raw symbol list generated by `ai-workspace bootstrap`. Contains no verified execution flows. | Ask `/codebase-memory` to complete the domain using `slice` $\rightarrow$ becomes **`[STATIC]`**. |
| **`[STATIC]`** | Call graphs, structs, and invariants have been traced directly from source code, but not yet executed/tested in this flow. | Provide runtime test results, logs, or hardware verification details $\rightarrow$ becomes **`[VERIFIED]`**. |
| **`[VERIFIED]`** | Confirmed at runtime with recorded test command, environment, and git commit SHA. | Automatically transitions to **`[NEEDS_REVERIFY]`** when `git commit` or `git merge` modifies a tracked function in that domain. |
| **`[NEEDS_REVERIFY]`** | A source file/function in this domain was modified. Warning banner lists the exact `modified symbols`. | Ask `/codebase-memory` to reconcile the modified symbols against `git diff` $\rightarrow$ returns to **`[STATIC]`** or **`[VERIFIED]`**. |

---

## 5. Best Practices for Maximum Token Economy & Speed

1. **Keep Domain Scopes Focused (Sub-Domain Hierarchy):**
   - Instead of bootstrapping a massive top-level folder with 3,000 files into one giant `driver.md`, split it by functional sub-domain: `net/tx_datapath`, `net/rx_datapath`, `net/control_plane`.
   - Smaller domain files (~100–250 lines) load in ~800 tokens and give the agent laser-sharp focus.
2. **Invest 10 Minutes in `.ai/conventions.md` Early:**
   - Document your project's custom allocators, error return macros, lock hierarchy, and IPC rules in `.ai/conventions.md` once. Every future `/codebase-memory` session will enforce those rules automatically during code generation and code review.
3. **Let `slice` and `refresh-coords` Do the Heavy Lifting:**
   - When writing prompts or editing domain files, always keep symbol coordinates in the canonical format:
     - Functions: `` `func_name()` (`path/to/file.c:123`) ``
     - Structs/Classes: `` `struct my_ctx` (`path/to/header.h:45`) ``
   - This allows `./.ai/ai-workspace refresh-coords` to heal shifted line numbers in milliseconds without spending a single LLM token.
4. **Enrich Routing Keywords in `.ai/index.md`:**
   - Include common error strings, daemon names, and CLI commands in the `Keywords & Symptoms` column of `.ai/index.md`. When a user pastes a crash log containing that daemon or error string, the agent immediately routes to the right domain on the first read.

---

## 6. Anti-Patterns to Avoid

| Anti-Pattern | Why It Hurts | Do This Instead |
| :--- | :--- | :--- |
| Running `ai-workspace bootstrap` again on an already-completed `[STATIC]` or `[VERIFIED]` domain | Overwrites your curated execution flows and notes with a fresh `[SKELETON]` template. | Edit `.ai/domains/<domain>.md` in place, or ask `/codebase-memory Update knowledge for <domain>` (which updates in place). |
| Asking the agent to "document the entire repository" in one prompt | Creates dozens of shallow files and exhausts the context window. | Bootstrap and complete 1 domain at a time as you work on those modules. |
| Marking a domain `[VERIFIED]` just because the code compiled cleanly | Compilation only proves syntax, not runtime behavior or lock safety. | Use `[STATIC]` for source-traced knowledge; reserve `[VERIFIED]` for flows confirmed by tests or runtime logs. |
| Manually updating shifted line numbers after editing a file | Slow and error-prone. | Run `./.ai/ai-workspace refresh-coords [domain]` (or let `git commit` run `sync` automatically). |

---

## 7. Quick Cheat Sheet

| Goal | Command or Prompt |
| :--- | :--- |
| **See workspace health & suggested prompts** | `./.ai/ai-workspace status` |
| **Create or update knowledge for a feature** | `/codebase-memory Add knowledge for <feature_name>` |
| **Explain a flow using cached knowledge** | `/codebase-memory Explain <flow> in <domain> with file:line coordinates` |
| **Review staged code against project rules** | `/codebase-memory Review my staged changes` |
| **Audit app or commit for SDK architecture compliance** | `/codebase-memory Perform an architecture compliance review of <path_or_commit>` |
| **Refresh a domain flagged `[NEEDS_REVERIFY]`** | `/codebase-memory Reverify [NEEDS_REVERIFY] claims in .ai/domains/<domain>.md` |
| **Record a tough bug into `lessons_learned.md`** | `/codebase-memory Record this runtime trap in .ai/lessons_learned.md: <details>` |
| **Inspect a single function from terminal** | `./.ai/ai-workspace slice <function_or_struct_name>` |
| **Heal shifted line numbers across all domains** | `./.ai/ai-workspace refresh-coords` |
