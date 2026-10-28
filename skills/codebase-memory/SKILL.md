---
name: codebase-memory
description: Use when navigating unfamiliar code, creating or updating .ai/ knowledge, reviewing diffs, commits, or architecture compliance, debugging runtime behavior, or tempted to grep broadly or mark compiled code as verified.
---

# Codebase Memory

Use `.ai/` as a routing cache backed by source and runtime evidence. **Never invent claims, verify notes against source, and keep the active task as the strict boundary for investigation and updates.**

## When to Use

- Navigating unfamiliar modules, execution flows, locking/ownership rules (`.ai/conventions.md`), or runtime traps (`.ai/lessons_learned.md`).
- Reviewing source files, staged diffs, PRs, or commits.
- Creating, bootstrapping, refreshing, or updating `.ai/` domain knowledge.

**Skip when:** Making trivial single-line/typo edits, mechanical formatter fixes, or answering questions unrelated to the repository.

## Quick Reference

### Workflow Selection

| Task / Intent | Workflow | Authorization & Evidence Target |
| --- | --- | --- |
| Create/refresh knowledge | Read [references/create-update.md](references/create-update.md) | Pre-authorized to bootstrap/edit `.ai/`; target `[STATIC]` or `[VERIFIED]` |
| Review code or commits | Sections 1 -> 2 -> 3 | Read-only analysis; ask before editing `.ai/` unless updates requested |
| Architecture / app compliance review | Read [references/architecture-review.md](references/architecture-review.md) | Audit against `.ai/conventions.md` & arch domains; ask before editing `.ai/` |
| Navigate or debug | Sections 1 -> 2 -> 4 | Trace coordinates; persist reusable findings & traps |

### Allowed Status Markers (Only These Four)

| Marker | Meaning | Verification Rule |
| --- | --- | --- |
| `[SKELETON]` | Unreviewed generated symbols. | Inspect source before relying on claims. |
| `[STATIC]` | Verified from source inspection only. | Record what remains untested at runtime. |
| `[VERIFIED]` | Confirmed by runtime log, trace, or test. | Record test command, environment, output, and git revision. |
| `[NEEDS_REVERIFY]` | Tracked source changed; evidence stale. | Recheck affected claims against source/diff before use. |

## 1. Load Relevant Context

1. **Read `.ai/index.md` First:** Complete this before broad `rg` or `find`. If missing/unreadable, report the gap and run scoped source searches.
2. **Load Matching Domain:** Select the most specific `.ai/domains/<module>.md` or `<parent>/<submodule>.md`; expand only when flows cross boundaries.
3. **Check Global Invariants:** Read `.ai/conventions.md` (ownership, locking) and `.ai/lessons_learned.md` (runtime traps).
4. **Slice Exact Coordinates:** Jump to recorded `path:line` or run `bash ./.ai/ai-workspace slice <symbol|file:line>` instead of reading wide file ranges. If lines drifted, run `bash ./.ai/ai-workspace refresh-coords [domain]` before widening search.

## 2. Verify Claims Against Evidence

- A clean build or diff alone is **`[STATIC]`**, never **`[VERIFIED]`**.
- Assign `[VERIFIED]` strictly to flows proven by recorded runtime commands/tests.
- If runtime execution is unavailable, retain `[STATIC]` and state untested paths.
- Clear `[NEEDS_REVERIFY]` and warning banners only after all affected claims are rechecked.

## 3. Review Source Files or Commits

Missing `.ai/` knowledge means inspect source directly—never halt a review.

1. **Establish Scope:** Inspect working tree (keep staged vs. unstaged separate), commit vs. parent, or merge vs. first parent.
2. **Route Through Knowledge:** Check `.ai/index.md`, domains, `.ai/conventions.md`, and `.ai/lessons_learned.md` for invariants; read historical revisions via `git show` without altering checkout.
3. **Trace Source Directly:** Where knowledge is missing or stale, trace callers, callees, lifecycles, locks, and tests.
4. **Output Format (Positive Recipe):**
   1. **Findings first**, ordered by severity (correctness, regressions, leaks, concurrency, test gaps; distinguish new vs. pre-existing), each with `path:line`, trigger, impact, and evidence.
   2. **Review limitations** and unverified execution paths.
   3. **Separate `.ai/` proposals** at the end: target file, updated claim, coordinates, and proposed status marker. Ask permission before editing `.ai/` on review-only requests.

## 4. Persist Reusable Findings

| Finding Type | Destination | Required Format |
| --- | --- | --- |
| Flows, ownership, symbols | `.ai/domains/<module>.md` | Header `**Overall Status:**` + `` `symbol()` (`path/to/file:line`) `` |
| Cross-cutting rules | `.ai/conventions.md` | Allocators, locking hierarchy, IPC invariants |
| Runtime traps | `.ai/lessons_learned.md` | Symptom, root cause, trigger, resolution |

- **Canonical Coordinates:** Always format symbols as `` `symbol_name()` (`path/to/file:line`) `` or `` `struct name` (`path/to/file:line`) `` so `slice` and `refresh-coords` parse them cleanly.
- **Sanitization:** Keep all `.ai/` entries 100% generic—no customer names, vendor identifiers, credentials, or keys.
- **Workspace & Index Sync:** Resolve `.ai/` symlinks / `AI_WORKSPACE_DIR`. CLI commands (`bootstrap`, `reindex`, `refresh-coords`, `sync`) stage only their target files, preserving WIP. Update `**Overall Status:**` in the domain header and run `bash ./.ai/ai-workspace reindex` (preserves all 4 status markers) or update `.ai/index.md` directly.

## 5. Contextual Next-Step Suggestions

Append a 1–2 line actionable next step **only** when one of these holds (omit if `[VERIFIED]` and current):
- Explored an unindexed or `[SKELETON]` module -> suggest saving the traced flow to `.ai/domains/<module>.md` as `[STATIC]`.
- Consulted a `[NEEDS_REVERIFY]` domain -> suggest reconciling modified symbols against `git diff`.
- Resolved a non-obvious runtime bug -> suggest recording it in `.ai/lessons_learned.md` and promoting the flow to `[VERIFIED]`.

## Common Mistakes & Rationalizations

| Excuse | Reality |
| --- | --- |
| "Grepping is faster than reading `.ai/index.md`" | Broad search wastes tokens and misses documented traps in `lessons_learned.md`. Check `.ai/index.md` first. |
| "Read 200 lines around a coordinate" | Use `bash ./.ai/ai-workspace slice <symbol\|file:line>` for exact block extraction. |
| "Build succeeded, mark it `[VERIFIED]`" | Compilation only checks syntax/types. `[VERIFIED]` requires runtime evidence; keep `[STATIC]`. |
| "Edit `.ai/` immediately during a code review" | Review-only prompts authorize proposals, not `.ai/` writes. Propose separately and ask permission. |
| "Skip `**Overall Status:**` or use `Status:`" | `reindex` parses `**Overall Status:**`; missing or non-standard headers reset index status to `[SKELETON]`. |

## Red Flags - STOP and Check

- Running broad `rg`/`grep` before reading `.ai/index.md`.
- Marking `[VERIFIED]` without runtime command/test output.
- Editing `.ai/` during a review without authorization.
- Re-running `bootstrap` on an existing domain (overwrites manual notes).
- Writing non-canonical coordinates (`func in file.c:10`) or leaving `**Overall Status:**` as `[SKELETON - UNVERIFIED]`.
