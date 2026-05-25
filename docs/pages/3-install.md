---
title: Installation & Setup
nav_order: 3
permalink: /install
---

# Installation & Setup

Choose the package surface that matches your app and backend model.

## Plain Ruby with memory or Redis

```ruby
gem "kaal"
```

Install dependencies and generate the starter files:

```bash
bundle install
bundle exec kaal init --backend=memory
```

For Redis:

```bash
bundle exec kaal init --backend=redis
```

`kaal init` writes:

- `config/kaal.yml`
- `config/kaal-scheduler.yml`

Use this path when you want:

- local development with no external coordination store
- Redis-backed coordination without SQL persistence

## Plain Ruby with Sequel-backed SQL persistence

```ruby
gem "kaal"
gem "sequel"
```

Use this when you want SQL persistence outside Rails and your app already uses Sequel or can provide a Sequel connection.

Typical choices:

- SQLite for a simple single-node install
- PostgreSQL for distributed advisory-lock coordination
- MySQL for named-lock coordination

Example `config/kaal.yml`:

```yaml
defaults:
  backend: sqlite
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    url: db/kaal.sqlite3
```

You are responsible for creating the Kaal tables through the Sequel adapter path.

## Plain Ruby with Active Record-backed SQL persistence

```ruby
gem "kaal"
gem "activerecord"
```

Use this when you want Active Record-backed SQL persistence outside Rails.

Example `config/kaal.yml`:

```yaml
defaults:
  backend: sqlite
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    connection:
      adapter: sqlite3
      database: db/kaal.sqlite3
```

You are responsible for creating the Kaal tables through the Active Record adapter path.

## Rails

```ruby
gem "kaal-rails"
```

Use `kaal-rails` when you want the Rails-native install surface, generators, tasks, and Active Record-backed persistence.

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

Use `kaal-sinatra` when you want supported Sinatra wiring across memory, Redis, or Sequel-backed SQL.

Typical setup:

- choose one backend path: `backend:`, `redis:`, or `database:`
- provide `config/kaal-scheduler.yml`
- wire the app with `Kaal::Sinatra.register!` or the Sinatra extension
- start the scheduler explicitly only when you want the web process to host it

For SQL persistence, create the Kaal tables through Sequel migrations.

## Roda

```ruby
gem "kaal-roda"
```

Use `kaal-roda` when you want supported Roda wiring across memory, Redis, or Sequel-backed SQL.

Typical setup:

- choose one backend path: `backend:`, `redis:`, or `database:`
- provide `config/kaal-scheduler.yml`
- wire the app with `plugin :kaal` and `kaal(...)`
- start the scheduler explicitly only when you want the web process to host it

For SQL persistence, create the Kaal tables through Sequel migrations.

## Hanami

```ruby
gem "kaal-hanami"
```

Use `kaal-hanami` when you want supported Hanami wiring across memory, Redis, or Sequel-backed SQL.

Typical setup:

- choose one backend path: `backend:`, `redis:`, or `database:`
- provide `config/kaal-scheduler.yml`
- wire the app with `Kaal::Hanami.configure!(self, ...)`
- start the scheduler explicitly only when you want the web process to host it

For SQL persistence, create the Kaal tables through Sequel migrations.

## Verify setup

Use the scheduler CLI against your configured project:

```bash
bundle exec kaal status --config config/kaal.yml
```

If the app is configured correctly, `status` will print the current runtime settings and loaded job keys.
