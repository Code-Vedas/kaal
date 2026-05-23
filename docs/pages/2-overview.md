---
title: Overview & Motivation
nav_order: 2
permalink: /overview
---

# Overview & Motivation

Kaal is a distributed cron scheduler for Ruby, packaged as a core engine plus datastore and framework integration gems.

It exists to solve one problem cleanly: coordinate scheduled work across processes or nodes without duplicating scheduler dispatches.

## What it owns

Kaal handles:

- cron parsing and next-fire calculation
- recurring job registration
- delayed-job persistence and dispatch
- scheduler ticking and coordination
- shared-backend dispatch tracking
- deterministic `idempotency_key` generation for downstream dedupe

Kaal does not require a specific job system. Your callback can enqueue Active Job, Sidekiq, Resque, or your own service object.

## Why Kaal

- plain Ruby runtime with no framework requirement
- package boundaries split between the core engine and framework integrations
- memory and Redis support in the core gem
- Sequel and Active Record SQL paths inside the core gem
- CLI tools for setup and operations
- documented at-most-once dispatch guarantee for supported shared backends

## Package roles

- `kaal`
  Core engine, runtime coordination, CLI, memory backend, Redis backend, and optional SQL backend surfaces.
- `kaal-rails`
  Rails integration that builds on `kaal`.
- `kaal-hanami`
  Hanami integration that builds on `kaal`.
- `kaal-roda`
  Roda integration that builds on `kaal`.
- `kaal-sinatra`
  Sinatra integration that builds on `kaal`.

## Where it fits

Pick the package surface that matches your application:

- plain Ruby + memory, Redis, Sequel SQL, or Active Record SQL: `kaal`
- Rails: `kaal-rails`
- Hanami: `kaal-hanami`
- Roda: `kaal-roda`
- Sinatra: `kaal-sinatra`

The runtime API remains the same across adapters: define jobs, configure a backend, and run the scheduler.
