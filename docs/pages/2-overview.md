---
title: Overview & Motivation
nav_order: 2
permalink: /overview
---

# Overview & Motivation

Kaal is a distributed cron scheduler for Ruby, packaged as a core engine plus adapter gems.

It exists to solve one problem cleanly: schedule recurring work across multiple processes or nodes without duplicating dispatches.

## Why Kaal

- Ruby-first runtime with no framework dependency
- Single-dispatch coordination across nodes
- Thor CLI for initialization and operations
- Split package boundaries for engine, datastore adapters, and framework integrations
- Memory and redis support in the core gem
- SQL persistence through Sequel or Active Record adapter gems
- Built-in cron validation, linting, simplification, and humanization

## Where It Fits

`kaal` handles scheduling and dispatch coordination. Your callback decides what to run:

- call a job object
- enqueue to Sidekiq or another queue
- invoke service objects directly
- trigger shell-safe application code

## Package Roles

- `kaal`
  Core engine, runtime coordination, CLI, memory backend, redis backend
- `kaal-sequel`
  Sequel-backed SQL datastore adapter
- `kaal-activerecord`
  Active Record-backed SQL datastore adapter
- `kaal-rails`
  Rails plugin that uses `kaal` plus `kaal-activerecord`
- `kaal-roda`
  Roda addon with explicit framework wiring for memory, redis, and SQL backends
- `kaal-sinatra`
  Sinatra addon with explicit framework wiring for memory, redis, and SQL backends
