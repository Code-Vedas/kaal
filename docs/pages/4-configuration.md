---
title: Configuration
nav_order: 4
permalink: /configuration
---

# Configuration

Primary runtime configuration lives in `config/kaal.yml`.

## Core engine example

```yaml
defaults:
  backend: memory
  namespace: kaal
  tick_interval: 5
  window_lookback: 120
  window_lookahead: 0
  lease_ttl: 125
  scheduler_config_path: config/kaal-scheduler.yml
  enable_dispatch_recovery: true
  enable_log_dispatch_registry: false
  delayed_job_allowed_class_prefixes: []
  backend_config: {}
```

For the documented at-most-once dispatch guarantee, enable the dispatch log registry and keep `lease_ttl >= window_lookback + tick_interval`. See [At-Most-Once Dispatch Guarantee](/dispatch-guarantee).

## Delayed-job configuration

Delayed jobs reuse the configured backend. No separate delayed-job backend setting exists.

Optional delayed-job class restrictions are prefix-based:

```yaml
defaults:
  delayed_job_allowed_class_prefixes:
    - Reports::
    - Billing::
```

Behavior:

- an empty array means unrestricted delayed-job class names
- restrictions are checked both when enqueueing and when dispatching
- this setting applies to delayed jobs only; recurring scheduler-file jobs continue to use the scheduler-file validation rules

For local or otherwise trusted deployments, an empty list is valid. On shared Redis or SQL backends in production, configure a restrictive prefix list. Kaal warns on startup when delayed-job class resolution is unrestricted in that kind of deployment.

## Sequel adapter example

```yaml
defaults:
  backend: sqlite
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    url: db/kaal.sqlite3
```

Alternative SQL backends:

Use `backend: postgres` or `backend: mysql` with `backend_config.url`.

## Active Record adapter example

```yaml
defaults:
  backend: sqlite
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    connection:
      adapter: sqlite3
      database: db/kaal.sqlite3
```

Alternative SQL backends:

Use `backend: postgres` or `backend: mysql` with `backend_config.url` or `KAAL_BACKEND_URL`.

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

`kaal-rails` now installs `config/kaal.yml`; if that file omits `backend`, Rails adapter detection still fills it in.

## Sinatra addon behavior

When you use `kaal-sinatra`, the addon chooses the backend in this order:

- preserve `Kaal.configuration.backend` if one is already set
- load `config/kaal.yml` first
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
  scheduler_config_path: "config/kaal-scheduler.yml",
  namespace: "my-app",
  start_scheduler: false
)
```

Redis setup:

```ruby
require "redis"

redis = Redis.new(url: "redis://127.0.0.1:6379/0")

Kaal::Sinatra.register!(
  settings,
  redis: redis,
  scheduler_config_path: "config/kaal-scheduler.yml"
)
```

Set `backend: memory|redis|sqlite|postgres|mysql` in `config/kaal.yml` for the primary runtime path.

## Roda addon behavior

When you use `kaal-roda`, the addon chooses the backend in this order:

- preserve `Kaal.configuration.backend` if one is already set
- load `config/kaal.yml` first
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

  kaal scheduler_config_path: "config/kaal-scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

Redis setup:

```ruby
require "redis"

redis = Redis.new(url: "redis://127.0.0.1:6379/0")

class App < Roda
  plugin :kaal

  kaal redis: redis,
       scheduler_config_path: "config/kaal-scheduler.yml"
end
```

Set `backend` and `backend_config` in `config/kaal.yml` for the primary runtime path.

## Hanami addon behavior

When you use `kaal-hanami`, the addon chooses the backend in this order:

- preserve `Kaal.configuration.backend` if one is already set
- load `config/kaal.yml` first
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
      scheduler_config_path: "config/kaal-scheduler.yml",
      namespace: "my-app",
      start_scheduler: false
    )
  end
end
```

Redis setup:

```ruby
require "redis"

redis = Redis.new(url: "redis://127.0.0.1:6379/0")

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(self, redis: redis, scheduler_config_path: "config/kaal-scheduler.yml")
  end
end
```

Set `backend` and `backend_config` in `config/kaal.yml` for the primary runtime path.

## Key Options

| Setting                        | Default                  | Meaning                                                                |
| ------------------------------ | ------------------------ | ---------------------------------------------------------------------- |
| `backend`                      | `nil`                    | Runtime backend name such as `memory`, `redis`, `sqlite`, `postgres`, or `mysql` |
| `backend_config`               | `{}`                     | Backend connection settings; `KAAL_BACKEND_URL` overrides `backend_config.url` |
| `tick_interval`                | `5`                      | Seconds between scheduler ticks                                        |
| `window_lookback`              | `120`                    | Recovery window for missed runs                                        |
| `window_lookahead`             | `0`                      | Optional future lookahead                                              |
| `lease_ttl`                    | `125`                    | Lock TTL for TTL-based adapters                                        |
| `namespace`                    | `"kaal"`                 | Prefix for coordination keys                                           |
| `time_zone`                    | `nil`                    | Scheduler interpretation zone; defaults to UTC                         |
| `scheduler_config_path`        | `"config/kaal-scheduler.yml"` | Scheduler file path                                                    |
| `enable_dispatch_recovery`     | `true`                   | Replay missed runs on startup                                          |
| `enable_log_dispatch_registry` | `false`                  | Persist dispatch records used by the documented at-most-once guarantee |

## Time Zone Rules

- If `time_zone` is set, that zone is used to interpret cron expressions.
- If `time_zone` is unset, Kaal uses `UTC`.
