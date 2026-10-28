# Create or Update Knowledge

Use when the user asks to create, add, supplement, refresh, or update `.ai/` knowledge (e.g., `/codebase-memory Add knowledge for wireless interference`). Maintain source-backed knowledge in place rather than duplicating domains.

| Condition | Action | Command |
| --- | --- | --- |
| No `.ai/` workspace yet | Provision workspace | `bash /path/to/aiws/ai-workspace init` |
| Domain file missing | Bootstrap skeleton | `bash ./.ai/ai-workspace bootstrap <domain> <paths>` |
| Domain file exists (incl. stale/unindexed) | Heal line drift & edit in place | `bash ./.ai/ai-workspace refresh-coords <domain>` |
| Inspecting function/struct code | Surgical extraction | `bash ./.ai/ai-workspace slice <symbol\|file:line>` |

## 1. Resolve Feature & Workspace

1. Check `.ai/index.md`, domain filenames, and headings for an existing match before creating a new domain.
2. If paths are omitted, search feature terms to infer repository-relative files/directories; ask only if multiple unrelated implementations exist.
3. Choose a lowercase relative domain path (e.g., `wireless/interference`) with no parent traversal.
4. Run commands from the repository root; resolve `.ai/` symlinks and set `AI_WORKSPACE_DIR` if pointing to an external workspace.
5. If `.ai/` is absent, run `ai-workspace init` (preserves existing `AGENTS.md` and appends Git hooks idempotently). If CLI is unavailable, copy `templates/_template.md` and note the gap.

## 2. Create or Update Domain File

Check the physical file path, not just its `.ai/index.md` row:
- **Missing file** (even with dangling index row): run `bash ./.ai/ai-workspace bootstrap <domain> <paths>`. Never re-run `bootstrap` on an existing domain—it overwrites manual notes.
- **Existing file**: run `bash ./.ai/ai-workspace refresh-coords <domain>` to auto-heal shifted line numbers, then edit in place.

*(All CLI commands stage only their target domain and `.ai/index.md`, leaving unrelated uncommitted WIP untouched.)*

## 3. Complete & Reconcile Knowledge

1. Inspect key entry points, structs, and callbacks using `bash ./.ai/ai-workspace slice <symbol|file:line>`.
2. Replace placeholders with purpose, call flows, branches, resource ownership, configuration, and traps using canonical `` `symbol_name()` (`path/to/file:line`) `` coordinates. Record explicit gaps if evidence is unavailable.
3. Set `**Overall Status:**` (`[STATIC]` for source-traced, `[VERIFIED]` only with runtime command/revision evidence; clear `[NEEDS_REVERIFY]` only for rechecked claims).
4. Sync `.ai/index.md` via `bash ./.ai/ai-workspace reindex` (or targeted row edits for custom keywords).
5. Report modified files, whether `bootstrap` ran, the evidence level, and any remaining gaps.
