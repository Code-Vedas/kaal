# Kaal::Sinatra

Sinatra integration gem for Kaal.

`kaal-sinatra` depends on:

- `kaal`
- `kaal-sequel`
- `sinatra`

It owns the Sinatra integration surface:

- explicit boot wiring for Sinatra apps
- backend wiring for memory, redis, SQLite, PostgreSQL, and MySQL
- scheduler file boot loading relative to the Sinatra app root
- opt-in scheduler startup and shutdown helpers
- Sinatra-specific test coverage and dummy apps

## Install

```ruby
gem 'kaal-sinatra'
gem 'redis'   # for redis
gem 'sqlite3' # or pg / mysql2 for SQL
```

If you use SQL persistence, create the Kaal tables using Sequel migrations. `kaal-sequel` exposes templates for:

- SQLite: `kaal_dispatches`, `kaal_locks`, `kaal_definitions`
- PostgreSQL: `kaal_dispatches`, `kaal_definitions`
- MySQL: `kaal_dispatches`, `kaal_definitions`

Your app should also provide `config/scheduler.yml`.

## What It Provides

- Sinatra-native wiring on top of the Kaal engine
- explicit backend injection for memory and custom backends
- redis convenience wiring when the app passes a redis client
- automatic SQL backend selection from the Sequel adapter unless the app passes `adapter:`
- explicit lifecycle helpers so web processes do not implicitly start background scheduler threads

## Classic Sinatra

```ruby
require 'sinatra'
require 'kaal/sinatra'

class ExampleHeartbeatJob
  def self.perform(*)
    puts 'heartbeat'
  end
end

register Kaal::Sinatra::Extension

Kaal::Sinatra.register!(
  settings,
  backend: Kaal::Backend::MemoryAdapter.new,
  scheduler_config_path: 'config/scheduler.yml',
  namespace: 'my-app',
  start_scheduler: false
)
```

## Modular Sinatra

```ruby
require 'sinatra/base'
require 'redis'
require 'kaal/sinatra'

class ExampleHeartbeatJob
  def self.perform(*)
    puts 'heartbeat'
  end
end

class App < Sinatra::Base
  REDIS = Redis.new(url: ENV.fetch('REDIS_URL'))

  register Kaal::Sinatra::Extension

  kaal redis: REDIS,
       scheduler_config_path: 'config/scheduler.yml',
       namespace: 'my-app',
       start_scheduler: false
end
```

## SQL Backends

For SQL-backed Sinatra apps, pass a Sequel connection:

```ruby
require 'sequel'

database = Sequel.connect(ENV.fetch('DATABASE_URL'))

Kaal::Sinatra.register!(
  settings,
  database: database,
  adapter: 'postgres', # optional when Sequel can infer it
  scheduler_config_path: 'config/scheduler.yml'
)
```

## Lifecycle

`kaal-sinatra` does not auto-start the scheduler by default.

If you want the web process to run it:

```ruby
Kaal::Sinatra.start!
```

To stop it explicitly:

```ruby
Kaal::Sinatra.stop!
```

If you pass `start_scheduler: true` to the extension or `Kaal::Sinatra.register!`, the addon starts the scheduler and installs an `at_exit` shutdown hook for that managed scheduler instance.

Preferred deployment model:

- run the scheduler in a dedicated process when possible
- use web-process startup only when you intentionally want co-located scheduling

## Public API

- `Kaal::Sinatra.register!(app, backend: nil, database: nil, redis: nil, scheduler_config_path: 'config/scheduler.yml', namespace: nil, start_scheduler: false, adapter: nil)`
- `Kaal::Sinatra.configure_backend!(backend: nil, database: nil, redis: nil, adapter: nil, configuration: Kaal.configuration)`
- `Kaal::Sinatra.load_scheduler_file!(root:, environment: nil)`
- `Kaal::Sinatra.start!`
- `Kaal::Sinatra.stop!`

## Development

```bash
bin/rspec-unit
bin/rspec-e2e memory
REDIS_URL=redis://127.0.0.1:6379/0 bin/rspec-e2e redis
bin/rspec-e2e sqlite
DATABASE_URL=postgres://postgres:postgres@localhost:5432/kaal_test_auto bin/rspec-e2e pg
DATABASE_URL=mysql2://root:rootROOT!1@127.0.0.1:3306/kaal_test_auto bin/rspec-e2e mysql
bin/rubocop
bin/reek
```
