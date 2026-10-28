# Architecture Compliance Review

Use when checking whether a commit, PR, new module, or entire application conforms to the repository's SDK architecture, layering, ownership, and runtime contracts documented in `.ai/`.

## 1. Establish Architectural Baseline

Before inspecting the target code or diff:
1. Read `.ai/index.md` and load `.ai/conventions.md`, `.ai/lessons_learned.md`, and all architecture or cross-cutting domain files (e.g., `.ai/domains/arch/*.md`, plus the owning subsystem domains).
2. If architectural rules are missing or `[SKELETON]`/`[NEEDS_REVERIFY]`, inspect the reference SDK facades, headers, or sibling compliant apps via `bash ./.ai/ai-workspace slice <symbol>` and disclose the baseline gap in the report.

## 2. Five-Axis Compliance Audit

Evaluate the target commit, module, or application across all five axes (mark axes outside scope as `Not Applicable` or `Unverified`):

| Axis | What to Verify | Typical Non-Compliant Signals |
| --- | --- | --- |
| **1. Layering & Dependency Direction** | Calls flow strictly through approved public facades/APIs; build dependencies stay within allowed tiers. | Including private internal headers (`../../core/...`), calling lower-layer internal symbols, or linking disallowed internal libraries. |
| **2. Subsystem Ownership & Demarcation** | Responsibilities live in the owning daemon/module defined in `.ai/conventions.md` and domain docs. | Duplicating control/state logic inside an unrelated daemon or bypassing the owning subsystem's interface. |
| **3. IPC, Lifecycle & Event Routing** | Registers properly with service/process supervisor, uses standard IPC/event channels, handles init/shutdown gracefully. | Custom shadow sockets/polling loops replacing standard IPC, missing entity registration, or blocking startup ordering. |
| **4. Locking & Memory Ownership** | Follows lock ordering, context rules (interrupt vs. process), and cross-boundary buffer ownership. | Holding shared model/zone locks across blocking IPC or disk I/O; freeing or retaining borrowed buffers against contract. |
| **5. State Source-of-Truth & Build Isolation** | Persists/reads config via single authoritative manager; isolates build-mode/compile-time variants cleanly. | Direct file/persistent-store writes bypassing central config manager; mutating persistent state inside read-only getters; leaking mode-specific symbols across builds. |

## 3. Output Format (Positive Recipe)

Present the architecture review strictly in this order:
1. **Architectural Baseline & Scope:** Files/commits/application inspected, consulted `.ai/` baseline files (with status markers), and any baseline gaps.
2. **Compliance Verdict:** One of `COMPLIANT`, `PARTIAL / NEEDS_WORK`, or `NON_COMPLIANT`.
3. **Findings (Ordered by Severity):** Group or tag clearly as `[ARCH]` (layering, ownership, IPC, source-of-truth violations) and `[BUG]` (deadlocks, leaks, correctness defects). Include `path:line`, violated rule/invariant (citing `.ai/` or reference source), trigger, impact, and concrete remediation.
4. **Audit Coverage & Limitations:** Axes verified vs. unverified (e.g., static inspection only, missing runtime/build checks).
5. **Proposed `.ai/` Knowledge Updates:** Placed separately at the end. Never add a dangling row to `.ai/index.md` without a domain file, and never document non-compliant code as approved architecture (tag open violations if indexing is requested). Ask permission before writing `.ai/` unless knowledge updates were explicitly authorized.

## Common Mistakes

- **Treating layering or ownership bypasses as "minor style" because code compiles/runs:** Direct internal header access, shadow config writes, and lock-held IPC create ABI coupling, split-brain state, and multi-process deadlocks. Report them as blocking `[ARCH]`/`[BUG]` findings regardless of deadline pressure.
- **Auditing only diff lines on a new application:** Inspect build files (`Makefile`/`CMakeLists`), headers/includes, init/shutdown registration, and IPC entry points—not just isolated C syntax.
