---
title: Installation & Setup
nav_order: 3
permalink: /install
---

# Installation & Setup

Choose the package surface that matches your app.

## Plain Ruby with memory or Redis

```ruby
gem "kaal"
```

Install dependencies and generate the project files:

```bash
bundle install
bundle exec kaal init --backend=memory
```

`kaal init` writes:

- `config/kaal.rb`
- `config/scheduler.yml`

Use this path when you want:

- local development with no external coordination store
- Redis-backed coordination without SQL persistence

## Plain Ruby with Sequel-backed SQL persistence

```ruby
gem "kaal"
gem "kaal-sequel"
```

Use `kaal-sequel` when you want SQL persistence outside Rails.

Typical choices:

- SQLite for a single-node install
- PostgreSQL for distributed advisory locks
- MySQL for named locks

You are responsible for creating the Kaal tables through the Sequel adapter path.

## Plain Ruby with Active Record-backed SQL persistence

```ruby
gem "kaal"
gem "kaal-activerecord"
```

Use `kaal-activerecord` when you want Active Record-backed SQL persistence outside Rails.

## Rails with Active Record

```ruby
gem "kaal-rails"
```

Use `kaal-rails` when you want the Rails plugin surface, generators, tasks, and Active Record-backed persistence.

Typical setup:

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

PostgreSQL:

```bash
bundle exec rails generate kaal:install --backend=postgres
bundle exec rails db:migrate
```

MySQL:

```bash
bundle exec rails generate kaal:install --backend=mysql
bundle exec rails db:migrate
```

## Sinatra

```ruby
gem "kaal-sinatra"
```

Use `kaal-sinatra` when you want a supported Sinatra setup path across memory, redis, or SQL backends.

Typical setup:

- choose one backend path:
  - `backend:` for memory or a custom backend object
  - `redis:` for Redis-backed coordination
  - `database:` for Sequel-backed SQL
- provide `config/scheduler.yml`
- wire the app with `Kaal::Sinatra.register!` or the Sinatra extension
- start the scheduler explicitly only when you want the web process to host it

For SQL persistence, create the Kaal Sequel tables through migrations.

## Roda

```ruby
gem "kaal-roda"
```

Use `kaal-roda` when you want a supported Roda setup path across memory, redis, or SQL backends.

Typical setup:

- choose one backend path:
  - `backend:` for memory or a custom backend object
  - `redis:` for Redis-backed coordination
  - `database:` for Sequel-backed SQL
- provide `config/scheduler.yml`
- wire the app with `plugin :kaal` and `kaal(...)`
- start the scheduler explicitly only when you want the web process to host it

For SQL persistence, create the Kaal Sequel tables through migrations.

## Hanami

```ruby
gem "kaal-hanami"
```

Use `kaal-hanami` when you want a supported Hanami setup path across memory, redis, or SQL backends.

Typical setup:

- choose one backend path:
  - `backend:` for memory or a custom backend object
  - `redis:` for Redis-backed coordination
  - `database:` for Sequel-backed SQL
- provide `config/scheduler.yml`
- wire the app with `Kaal::Hanami.configure!(self, ...)` inside your `Hanami::App` class
- start the scheduler explicitly only when you want the web process to host it

For SQL persistence, create the Kaal Sequel tables through migrations.

## Core backend choices

- `memory`: no external store
- `redis`: external coordination through Redis

## Verify Setup

```bash
bundle exec kaal status --config config/kaal.rb
```
