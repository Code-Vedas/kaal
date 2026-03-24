---
title: At-Most-Once Dispatch Guarantee
nav_order: 6
permalink: /dispatch-guarantee
---

# At-Most-Once Dispatch Guarantee

Kaal guarantees at-most-once dispatch per `(key, fire_time)` for Redis, Postgres, and MySQL-backed deployments under the documented crash-and-restart model.

## What This Means

If multiple scheduler nodes observe the same due occurrence, Kaal dispatches that occurrence at most once.

For any given `(key, fire_time)`, Kaal also generates the same deterministic `idempotency_key`. That gives job code a stable dedupe key when it needs to extend Kaal's dispatch guarantee to downstream effects.

## Operational Assumptions

This guarantee applies when:

- all scheduler nodes share the same healthy Redis, Postgres, or MySQL backend
- `enable_log_dispatch_registry = true`
- `lease_ttl >= window_lookback + tick_interval`
- all nodes use the same namespace
- all nodes load the same scheduler definition set

## Documented Model

Kaal's dispatch guarantee is based on the following runtime model:

1. discover due occurrences for each registered scheduler entry
2. check whether `(key, fire_time)` is already present in the dispatch registry
3. attempt to claim the backend coordination lock for that occurrence
4. invoke the dispatch callback only when the occurrence is not already logged and the claim succeeds
5. record the dispatched occurrence in the active dispatch registry
6. on restart, repeat the same checks during recovery before replaying missed occurrences

The documented model covers:

- concurrent scheduler nodes
- repeated normal ticks
- process crash and restart
- normal backend reconnect behavior

It does not claim arbitrary network partition or split-brain storage guarantees.

## Evidence

Kaal backs this guarantee with three concrete evidence signals in the repository:

- coordinator regression coverage that proves repeated normal ticks skip an already-dispatched `(key, fire_time)`
- threaded contention specs across memory, Redis, and SQL-backed adapters
- multi-node CLI checks in CI for Redis, Postgres, and MySQL using two live `kaal start` processes against the same backend

Together, these checks validate the guarantee at the coordinator level, the adapter level, and the real process-orchestration level.

## Extending To Job Effects

Kaal guarantees dispatch semantics. To make downstream job effects effectively once as well, use the provided `idempotency_key` at the job boundary.

Examples:

- insert a row with a unique key on `idempotency_key` before sending an email
- record a payment or invoice attempt keyed by `idempotency_key`
- persist an outbound event log keyed by `idempotency_key` before publishing

## Boundary

Kaal guarantees at-most-once scheduler dispatch per `(key, fire_time)` under the documented model. Exactly-once effects in external systems still depend on the job's own idempotency handling.
