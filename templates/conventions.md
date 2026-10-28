# Project Engineering & Architectural Conventions

This file documents cross-cutting conventions, memory ownership rules, concurrency constraints, and architectural standards for the codebase.

## 1. Memory Management & Ownership Rules
- **Allocation & Deallocation:** Standard APIs for kernel, userspace, and abstraction layers (e.g., `kmalloc()`, `dma_alloc_coherent()`, `free()`).
- **Buffer Ownership:** Clear rules on whether the caller or callee is responsible for freeing request/response buffers.
- **DMA Buffers:** Alignment and cache-flushing constraints for ring descriptors and packet buffers.

## 2. Concurrency, Locking & Context Constraints
- **Lock Ordering:** Established hierarchy to prevent deadlocks when acquiring multiple spinlocks/mutexes.
- **Interrupt vs Process Context:** Strictly no sleeping or mutex acquisitions inside tasklet, bottom-half, or timer callbacks (`spin_lock_irqsave` vs `mutex_lock`).

## 3. Error Handling & Return Code Standards
- **Status Codes:** Standard return codes (e.g., `STATUS_OK`, `ERR_INVALID_ARG`, `-EINVAL`).
- **Cleanup Invariants:** Requirement to roll back partially allocated resources and release held locks before returning errors.

## 4. IPC & Subsystem Communication Conventions
- **Device & Subsystem IPC:** Ring buffer descriptors, register access protocols, and message queues.
- **Data Model & Configuration Handlers:** Configuration schema getter/setter validation and serialization conventions.
