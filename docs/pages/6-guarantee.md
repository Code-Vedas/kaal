---
title: At-Most-Once Dispatch Guarantee
nav_order: 6
permalink: /dispatch-guarantee
---

# At-Most-Once Dispatch Guarantee

Kaal guarantees at-most-once dispatch per `(key, fire_time)` for recurring jobs and at-most-once dispatch per `job_id` for delayed jobs on Redis, Postgres, and MySQL-backed deployments under the documented crash-and-restart model.

## What This Means

If multiple scheduler nodes observe the same due occurrence, Kaal dispatches that occurrence at most once.

If multiple scheduler nodes sweep the same due delayed job, Kaal dispatches that `job_id` at most once.

For any given `(key, fire_time)`, Kaal also generates the same deterministic `idempotency_key`. That gives job code a stable dedupe key when it needs to extend Kaal's dispatch guarantee to downstream effects.

Delayed jobs use caller-supplied `job_id` values instead of generated `idempotency_key` values. Choose stable `job_id` values when delayed-job enqueue operations themselves must be idempotent.

## Operational Assumptions

This guarantee applies when:

- all scheduler nodes share the same healthy Redis, Postgres, or MySQL backend
- `enable_log_dispatch_registry = true`
- `lease_ttl >= window_lookback + tick_interval`
- all nodes use the same namespace
- all nodes load the same scheduler definition set

For delayed jobs, the relevant assumptions are:

- all scheduler nodes share the same healthy delayed-job store for the configured backend
- all nodes use the same namespace and backend configuration
- all nodes can resolve the delayed job class at dispatch time unless the class is blocked by configuration

## Documented Model

Kaal's dispatch guarantee is based on the following runtime model:

1. discover due occurrences for each registered scheduler entry
2. check whether `(key, fire_time)` is already present in the dispatch registry
3. attempt to claim the backend coordination lock for that occurrence and, when the claim succeeds, log a dispatch attempt for `(key, fire_time)` in the active dispatch registry before invoking the callback
4. invoke the dispatch callback only when the occurrence is not already logged and the lock-claim/logging step succeeds
5. on restart, repeat the same registry check, lock-claim, and dispatch-attempt logging steps during recovery before replaying missed occurrences

The documented model covers:

- concurrent scheduler nodes
- repeated normal ticks
- process crash and restart
- normal backend reconnect behavior

For delayed jobs, the documented model is:

1. persist the delayed job in backend storage keyed by `job_id`
2. on each tick, sweep due delayed jobs in `run_at` order
3. atomically claim due delayed jobs from backend storage
4. dispatch the claimed job through the shared job dispatcher
5. if dispatch raises after claim, log the failure and do not retry automatically

Redis uses an atomic pop. Postgres and supported MySQL versions use `SKIP LOCKED`. Older SQL backends fall back to delete confirmation; that path remains correct, and Kaal adds a small pre-claim jitter to reduce synchronized contention between nodes.

It does not claim arbitrary network partition or split-brain storage guarantees.

## Evidence

Kaal backs this guarantee with three concrete evidence signals in the repository:

- coordinator regression coverage that proves repeated normal ticks skip an already-dispatched `(key, fire_time)`
- threaded contention specs for Redis and SQL-backed adapters
- multi-node CLI checks in CI for Redis, Postgres, and MySQL using two live `kaal start` processes against the same backend

Together, these checks validate the guarantee at the coordinator level, the adapter level, and the real process-orchestration level.

## Extending To Job Effects

Kaal guarantees dispatch semantics. To make downstream job effects effectively once as well, use the provided `idempotency_key` at the job boundary.

Examples:

- insert a row with a unique key on `idempotency_key` before sending an email
- record a payment or invoice attempt keyed by `idempotency_key`
- persist an outbound event log keyed by `idempotency_key` before publishing

## Boundary

Kaal guarantees at-most-once scheduler dispatch per `(key, fire_time)` for recurring work and at-most-once dispatch per `job_id` for delayed work under the documented model. Delayed jobs are deleted from storage before dispatch is attempted, so a failure after claim is treated as lost work and must be handled operationally or by the job producer. Exactly-once effects in external systems still depend on the job's own idempotency handling.
