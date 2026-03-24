---
title: Become a contributor
layout: page
nav_order: 10
permalink: /contribute
---

# Become a contributor

## Basic flow

1. Fork the repository.
2. Clone your fork and create a branch.
3. Install dependencies for the packages you are working on.
4. Make your changes.
5. Run the relevant checks.
6. Push and open a pull request.

## Monorepo structure

- `core/kaal`
  Core engine, runtime, CLI, memory backend, and Redis backend.
- `core/kaal-sequel`
  Sequel-backed SQL adapter.
- `core/kaal-activerecord`
  Active Record-backed SQL adapter.
- `gems/kaal-hanami`
  Hanami integration.
- `gems/kaal-rails`
  Rails integration.
- `gems/kaal-roda`
  Roda integration.
- `gems/kaal-sinatra`
  Sinatra integration.
- `docs/`
  Docs site source.
- `scripts/`
  Repo-level helpers for common checks.

## Common repo-level checks

Run these from the repo root:

```bash
scripts/run-rubocop-all
scripts/run-reek-all
scripts/run-rspec-unit-all
scripts/run-rspec-e2e-all
scripts/run-multi-node-cli-all
```

Or run the full monorepo check flow in one command:

```bash
scripts/run-all
```

Use the narrower scripts when you only need one phase. Use `scripts/run-all` when you want the full monorepo check flow.

## Package-level checks

You can also work from an individual package directory:

```bash
cd core/kaal
bundle install
bin/rspec-unit
bin/rubocop
bin/reek
```

Framework and adapter packages expose similar `bin/rspec-unit`, `bin/rspec-e2e`, `bin/rubocop`, and `bin/reek` entrypoints.

## What to contribute

Useful contributions include:

- scheduler/runtime improvements
- SQL or Redis adapter fixes
- framework integration improvements
- docs and examples
- test coverage and CI hardening

You do not need framework-specific experience to contribute. Plain Ruby, SQL, Redis, documentation, and test improvements are all useful.
