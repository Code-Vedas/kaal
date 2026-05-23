---
title: Configuration
nav_order: 4
permalink: /configuration
---

# Configuration

Primary runtime configuration lives in `config/kaal.rb`.

## Core engine example

```ruby
require "kaal"

Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
  config.tick_interval = 5
  config.window_lookback = 120
  config.window_lookahead = 0
  config.lease_ttl = 125
  config.namespace = "kaal"
  config.scheduler_config_path = "config/scheduler.yml"
  config.enable_dispatch_recovery = true
  config.enable_log_dispatch_registry = false
  config.delayed_job_allowed_class_prefixes = []
end
```

For the documented at-most-once dispatch guarantee, enable the dispatch log registry and keep `lease_ttl >= window_lookback + tick_interval`. See [At-Most-Once Dispatch Guarantee](/dispatch-guarantee).

## Delayed-job configuration

Delayed jobs reuse the configured backend. No separate delayed-job backend setting exists.

Optional delayed-job class restrictions are prefix-based:

```ruby
Kaal.configure do |config|
  config.delayed_job_allowed_class_prefixes = ["Reports::", "Billing::"]
end
```

Behavior:

- an empty array means unrestricted delayed-job class names
- restrictions are checked both when enqueueing and when dispatching
- this setting applies to delayed jobs only; recurring scheduler-file jobs continue to use the scheduler-file validation rules

For local or otherwise trusted deployments, an empty list is valid. On shared Redis or SQL backends in production, configure a restrictive prefix list. Kaal warns on startup when delayed-job class resolution is unrestricted in that kind of deployment.

## Sequel adapter example

```ruby
require "kaal"
require "sequel"

database = Sequel.connect(adapter: "sqlite", database: File.expand_path("../db/kaal.sqlite3", __dir__))

Kaal.configure do |config|
  config.backend = Kaal::Backend::SQLite.new(database: database)
  config.scheduler_config_path = "config/scheduler.yml"
end
```

Alternative SQL backends:

```ruby
config.backend = Kaal::Backend::Postgres.new(database: database)
config.backend = Kaal::Backend::MySQL.new(database: database)
```

## Active Record adapter example

```ruby
require "kaal"

Kaal.configure do |config|
  config.backend = Kaal::Backend::SQLite.new(
    connection: {
      adapter: "sqlite3",
      database: File.expand_path("../db/kaal.sqlite3", __dir__)
    }
  )
  config.scheduler_config_path = "config/scheduler.yml"
end
```

Alternative SQL backends:

```ruby
config.backend = Kaal::Backend::Postgres.new(connection: ENV.fetch("DATABASE_URL"))
config.backend = Kaal::Backend::MySQL.new(connection: ENV.fetch("DATABASE_URL"))
```

## Rails plugin behavior

When you use `kaal-rails`, the plugin selects a backend from the Rails database adapter unless you override it yourself:

- SQLite -> `Kaal::Backend::SQLite`
- PostgreSQL -> `Kaal::Backend::Postgres`
- MySQL -> `Kaal::Backend::MySQL`

Install flow examples:

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

Those migrations install the Kaal persistence schema used for both recurring and delayed jobs.

```bash
bundle exec rails generate kaal:install --backend=postgres
bundle exec rails db:migrate
```

```bash
bundle exec rails generate kaal:install --backend=mysql
bundle exec rails db:migrate
```

Explicit overrides still win:

```ruby
Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
end
```

## Sinatra addon behavior

When you use `kaal-sinatra`, the addon chooses the backend in this order:

- preserve `Kaal.configuration.backend` if one is already set
- use `backend:` when you pass an explicit backend object
- use `redis:` when you pass a redis client
- use `database:` and infer SQLite / PostgreSQL / MySQL from the Sequel adapter
- fall back to `Kaal::Backend::MemoryAdapter` when nothing else is provided

For SQL-backed Sinatra apps, the addon selects a backend from the Sequel adapter unless you pass `adapter:` explicitly:

- SQLite -> `Kaal::Backend::SQLite`
- PostgreSQL -> `Kaal::Backend::Postgres`
- MySQL -> `Kaal::Backend::MySQL`

Typical setup:

```ruby
require "kaal/sinatra"

Kaal::Sinatra.register!(
  settings,
  backend: Kaal::Backend::MemoryAdapter.new,
  scheduler_config_path: "config/scheduler.yml",
  namespace: "my-app",
  start_scheduler: false
)
```

Redis setup:

```ruby
require "redis"

redis = Redis.new(url: ENV.fetch("REDIS_URL"))

Kaal::Sinatra.register!(
  settings,
  redis: redis,
  scheduler_config_path: "config/scheduler.yml"
)
```

Explicit backend overrides still win:

```ruby
Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
end
```

## Roda addon behavior

When you use `kaal-roda`, the addon chooses the backend in this order:

- preserve `Kaal.configuration.backend` if one is already set
- use `backend:` when you pass an explicit backend object
- use `redis:` when you pass a redis client
- use `database:` and infer SQLite / PostgreSQL / MySQL from the Sequel adapter
- fall back to `Kaal::Backend::MemoryAdapter` when nothing else is provided

For SQL-backed Roda apps, the addon selects a backend from the Sequel adapter unless you pass `adapter:` explicitly:

- SQLite -> `Kaal::Backend::SQLite`
- PostgreSQL -> `Kaal::Backend::Postgres`
- MySQL -> `Kaal::Backend::MySQL`

Typical setup:

```ruby
require "kaal/roda"

class App < Roda
  plugin :kaal

  kaal backend: Kaal::Backend::MemoryAdapter.new,
       scheduler_config_path: "config/scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

Redis setup:

```ruby
require "redis"

redis = Redis.new(url: ENV.fetch("REDIS_URL"))

class App < Roda
  plugin :kaal

  kaal redis: redis,
       scheduler_config_path: "config/scheduler.yml"
end
```

Explicit backend overrides still win:

```ruby
Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
end
```

## Hanami addon behavior

When you use `kaal-hanami`, the addon chooses the backend in this order:

- preserve `Kaal.configuration.backend` if one is already set
- use `backend:` when you pass an explicit backend object
- use `redis:` when you pass a redis client
- use `database:` and infer SQLite / PostgreSQL / MySQL from the Sequel adapter
- fall back to `Kaal::Backend::MemoryAdapter` when nothing else is provided

For SQL-backed Hanami apps, the addon selects a backend from the Sequel adapter unless you pass `adapter:` explicitly:

- SQLite -> `Kaal::Backend::SQLite`
- PostgreSQL -> `Kaal::Backend::Postgres`
- MySQL -> `Kaal::Backend::MySQL`

Typical setup:

```ruby
require "kaal/hanami"

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(
      self,
      backend: Kaal::Backend::MemoryAdapter.new,
      scheduler_config_path: "config/scheduler.yml",
      namespace: "my-app",
      start_scheduler: false
    )
  end
end
```

Redis setup:

```ruby
require "redis"

redis = Redis.new(url: ENV.fetch("REDIS_URL"))

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(self, redis: redis, scheduler_config_path: "config/scheduler.yml")
  end
end
```

Explicit backend overrides still win:

```ruby
Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
end
```

## Key Options

| Setting                        | Default                  | Meaning                                                                |
| ------------------------------ | ------------------------ | ---------------------------------------------------------------------- |
| `backend`                      | `nil`                    | Coordination or datastore backend                                      |
| `tick_interval`                | `5`                      | Seconds between scheduler ticks                                        |
| `window_lookback`              | `120`                    | Recovery window for missed runs                                        |
| `window_lookahead`             | `0`                      | Optional future lookahead                                              |
| `lease_ttl`                    | `125`                    | Lock TTL for TTL-based adapters                                        |
| `namespace`                    | `"kaal"`                 | Prefix for coordination keys                                           |
| `time_zone`                    | `nil`                    | Scheduler interpretation zone; defaults to UTC                         |
| `scheduler_config_path`        | `"config/scheduler.yml"` | Scheduler file path                                                    |
| `enable_dispatch_recovery`     | `true`                   | Replay missed runs on startup                                          |
| `enable_log_dispatch_registry` | `false`                  | Persist dispatch records used by the documented at-most-once guarantee |

## Time Zone Rules

- If `time_zone` is set, that zone is used to interpret cron expressions.
- If `time_zone` is unset, Kaal uses `UTC`.
