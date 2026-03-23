# Kaal::Hanami

Hanami integration gem for Kaal.

`kaal-hanami` depends on:

- `kaal`
- `kaal-sequel`
- `hanami`

It owns the Hanami integration surface:

- explicit middleware-based boot wiring for Hanami apps
- backend wiring for memory, redis, SQLite, PostgreSQL, and MySQL
- scheduler file boot loading relative to the Hanami app root
- opt-in scheduler startup and shutdown helpers
- Hanami-specific test coverage and a dummy app

## Install

```ruby
gem 'kaal-hanami'
gem 'redis'   # for redis
gem 'sqlite3' # or pg / mysql2 for SQL
```

If you use SQL persistence, create the Kaal tables using Sequel migrations. `kaal-sequel` exposes templates for:

- SQLite: `kaal_dispatches`, `kaal_locks`, `kaal_definitions`
- PostgreSQL: `kaal_dispatches`, `kaal_definitions`
- MySQL: `kaal_dispatches`, `kaal_definitions`

Your app should also provide `config/scheduler.yml`.

## What It Provides

- Hanami-native middleware wiring on top of the Kaal engine
- explicit backend injection for memory and custom backends
- redis convenience wiring when the app passes a redis client
- automatic SQL backend selection from the Sequel adapter unless the app passes `adapter:`
- explicit lifecycle helpers so web processes do not implicitly start background scheduler threads

## Minimal Hanami

```ruby
require 'hanami'
require 'kaal/hanami'

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(
      self,
      backend: Kaal::Backend::MemoryAdapter.new,
      scheduler_config_path: 'config/scheduler.yml',
      namespace: 'my-app',
      start_scheduler: false
    )
  end
end
```

## Redis

```ruby
require 'redis'

module MyApp
  class App < Hanami::App
    REDIS = Redis.new(url: ENV.fetch('REDIS_URL'))

    Kaal::Hanami.configure!(
      self,
      redis: REDIS,
      scheduler_config_path: 'config/scheduler.yml',
      namespace: 'my-app',
      start_scheduler: false
    )
  end
end
```

## SQL Backends

For SQL-backed Hanami apps, pass a Sequel connection:

```ruby
require 'sequel'

database = Sequel.connect(ENV.fetch('DATABASE_URL'))

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(
      self,
      database: database,
      adapter: 'postgres', # optional when Sequel can infer it
      scheduler_config_path: 'config/scheduler.yml'
    )
  end
end
```

## Lifecycle

`kaal-hanami` does not auto-start the scheduler by default.

If you want the web process to run it:

```ruby
Kaal::Hanami.start!
```

To stop it explicitly:

```ruby
Kaal::Hanami.stop!
```

If you pass `start_scheduler: true` to `Kaal::Hanami.configure!`, the addon starts the scheduler and installs an `at_exit` shutdown hook for that managed scheduler instance.

Preferred deployment model:

- run the scheduler in a dedicated process when possible
- use web-process startup only when you intentionally want co-located scheduling

## Public API

- `Kaal::Hanami.configure!(app, **options)`
- `Kaal::Hanami.register!(app, backend: nil, database: nil, redis: nil, scheduler_config_path: 'config/scheduler.yml', namespace: nil, start_scheduler: false, adapter: nil, root: nil, environment: nil)`
- `Kaal::Hanami.configure_backend!(backend: nil, database: nil, redis: nil, adapter: nil, configuration: Kaal.configuration)`
- `Kaal::Hanami.detect_backend_name(database, adapter: nil)`
- `Kaal::Hanami.load_scheduler_file!(root:, environment: nil)`
- `Kaal::Hanami.start!`
- `Kaal::Hanami.stop!`
- `Kaal::Hanami::Middleware`
