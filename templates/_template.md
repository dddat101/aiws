# Module: <module_name>
**Source paths:** `<path_1> <path_2>`
**Last updated:** <YYYY-MM-DD>
**Overall Status:** `[TEMPLATE]`

## 1. Core Execution Flows (Call Graph)
- `[STATIC]` **Initialization Flow / Entry Point:**
  - `init_function()` (`path/to/file.c:100`) -> calls `subsystem_setup()` (`path/to/sub.c:50`)
- `[STATIC]` **Main Request / Event Processing Flow:**
  - `handle_event()` (`path/to/file.c:200`) -> dispatches to handler table.

## 2. Data Structures & Memory Ownership
- `struct module_ctx` (`path/to/source.h:45`)
  - Allocation / Lifecycle: Initialized during startup/fixture setup, cleaned up at shutdown/teardown.
  - Concurrency & Locking: Thread/task safety considerations.
  - Ownership: Single-owner vs shared reference rules.

## 3. Branching Points & Function Pointer Callbacks
- `event_cb` callback pointer (`path/to/file.c:85`)
- Tables of function pointers, event hooks, or `@pytest.fixture` injection points dynamically registered at runtime.

## 4. Symbol Coordinates
### Public API:
- `module_init()` (`path/to/file.c:100`)
- `module_process()` (`path/to/file.c:150`)

### Internal / Static:
- `helper_cleanup()` (`path/to/file.c:300`) [static]
