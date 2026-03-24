# Kaal

> Distributed cron scheduling for Ruby, split into a core engine plus datastore and framework integration gems.

[![Gem](https://img.shields.io/gem/v/kaal.svg?style=flat-square)](https://rubygems.org/gems/kaal)
[![CI](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)

Kaal coordinates recurring jobs across processes or nodes without changing how your app enqueues work. You choose the package surface that matches your runtime, define jobs in `config/scheduler.yml`, and run the scheduler in a dedicated process with `bundle exec kaal start`.

For Redis, Postgres, and MySQL-backed deployments, Kaal guarantees at-most-once dispatch per `(key, fire_time)` under the documented crash-and-restart model. Use the provided `idempotency_key` in your job boundary when downstream effects must also be deduplicated.

Project docs: <https://kaal.codevedas.com>

## Package selection

Choose the gem surface that matches your app:

- `kaal`
  Plain Ruby with in-process memory coordination or Redis coordination.
- `kaal` + `kaal-sequel`
  Plain Ruby with Sequel-backed SQL persistence.
- `kaal` + `kaal-activerecord`
  Plain Ruby with Active Record-backed SQL persistence.
- `kaal-rails`
  Rails integration with Active Record-backed persistence, generators, and rake tasks.
- `kaal-hanami`
  Hanami integration for memory, Redis, and Sequel-backed SQL.
- `kaal-roda`
  Roda integration for memory, Redis, and Sequel-backed SQL.
- `kaal-sinatra`
  Sinatra integration for memory, Redis, and Sequel-backed SQL.

## Monorepo layout

```text
/repo-root
├── core/
│   ├── kaal/              # Core engine gem, CLI, memory backend, redis backend
│   ├── kaal-sequel/       # Sequel-backed SQL adapter gem
│   └── kaal-activerecord/ # Active Record-backed SQL adapter gem
├── gems/
│   ├── kaal-hanami/       # Hanami integration gem
│   ├── kaal-rails/        # Rails integration gem
│   ├── kaal-roda/         # Roda integration gem
│   └── kaal-sinatra/      # Sinatra integration gem
├── docs/                  # Docs site source
├── scripts/               # Repo-level dev and CI entrypoints
└── README.md
```

## Quick start

Plain Ruby with the memory backend:

```ruby
gem "kaal"
```

```bash
bundle install
bundle exec kaal init --backend=memory
```

`kaal init` creates:

- `config/kaal.rb`
- `config/scheduler.yml`

Register a job in `config/scheduler.yml`:

```yaml
defaults:
  jobs:
    - key: "example:heartbeat"
      cron: "*/5 * * * *"
      job_class: "ExampleHeartbeatJob"
      enabled: true
      args:
        - "{{fire_time.iso8601}}"
      kwargs:
        idempotency_key: "{{idempotency_key}}"
```

Start and inspect the scheduler:

```bash
bundle exec kaal start
bundle exec kaal status
bundle exec kaal tick
bundle exec kaal explain "*/15 * * * *"
bundle exec kaal next "0 9 * * 1" --count 3
```

`kaal init` only supports `memory` and `redis`. For SQL-backed setups, add the appropriate adapter gem and configure the backend yourself, or use the framework-specific install surface.

## Installation paths

### Plain Ruby with memory or Redis

```ruby
gem "kaal"
```

Memory:

```bash
bundle exec kaal init --backend=memory
```

Redis:

```bash
bundle exec kaal init --backend=redis
```

### Plain Ruby with Sequel-backed SQL

```ruby
gem "kaal"
gem "kaal-sequel"
```

Example:

```ruby
require "kaal"
require "kaal/sequel"
require "sequel"

database = Sequel.connect(adapter: "sqlite", database: "db/kaal.sqlite3")

Kaal.configure do |config|
  config.backend = Kaal::Backend::DatabaseAdapter.new(database)
  config.scheduler_config_path = "config/scheduler.yml"
end
```

Use `Kaal::Backend::PostgresAdapter` or `Kaal::Backend::MySQLAdapter` for PostgreSQL and MySQL.

### Plain Ruby with Active Record-backed SQL

```ruby
gem "kaal"
gem "kaal-activerecord"
```

Example:

```ruby
require "kaal"
require "kaal/active_record"

Kaal::ActiveRecord::ConnectionSupport.configure!(
  adapter: "sqlite3",
  database: "db/kaal.sqlite3"
)

Kaal.configure do |config|
  config.backend = Kaal::ActiveRecord::DatabaseAdapter.new
  config.scheduler_config_path = "config/scheduler.yml"
end
```

Use `Kaal::ActiveRecord::PostgresAdapter` or `Kaal::ActiveRecord::MySQLAdapter` for PostgreSQL and MySQL.

### Rails

```ruby
gem "kaal-rails"
```

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

For PostgreSQL or MySQL, swap `sqlite` for `postgres` or `mysql`.

### Sinatra

```ruby
gem "kaal-sinatra"
```

Memory example:

```ruby
require "sinatra/base"
require "kaal/sinatra"

class App < Sinatra::Base
  register Kaal::Sinatra::Extension

  kaal backend: Kaal::Backend::MemoryAdapter.new,
       scheduler_config_path: "config/scheduler.yml",
       start_scheduler: false
end
```

### Roda

```ruby
gem "kaal-roda"
```

Memory example:

```ruby
require "roda"
require "kaal/roda"

class App < Roda
  plugin :kaal

  kaal backend: Kaal::Backend::MemoryAdapter.new,
       scheduler_config_path: "config/scheduler.yml",
       start_scheduler: false
end
```

### Hanami

```ruby
gem "kaal-hanami"
```

Memory example:

```ruby
require "hanami"
require "kaal/hanami"

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(
      self,
      backend: Kaal::Backend::MemoryAdapter.new,
      scheduler_config_path: "config/scheduler.yml",
      start_scheduler: false
    )
  end
end
```

## Operating Kaal

Run the scheduler in a dedicated process when possible.

Procfile:

```procfile
web: bundle exec puma -C config/puma.rb
scheduler: bundle exec kaal start
```

systemd:

```ini
[Service]
WorkingDirectory=/srv/my-app/current
ExecStart=/usr/bin/bash -lc 'bundle exec kaal start'
ExecStartPre=/usr/bin/bash -lc 'bundle exec kaal status'
Restart=always
```

Kubernetes:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-scheduler
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: scheduler
          image: my-app:latest
          command: ["bundle", "exec", "kaal", "start"]
```

Framework integrations can start the scheduler inside the web process, but that should be an intentional opt-in, not the default production model.

## Guarantee and idempotency

Kaal's scheduler-side guarantee is:

- at-most-once dispatch per `(key, fire_time)` for Redis, Postgres, and MySQL-backed deployments
- deterministic `idempotency_key` generation for the same `(key, fire_time)`

This guarantee depends on:

- all nodes sharing the same backend
- `enable_log_dispatch_registry = true`
- `lease_ttl >= window_lookback + tick_interval`
- all nodes sharing the same namespace and scheduler definition set

Kaal guarantees dispatch semantics, not exactly-once external side effects. Use `idempotency_key` at the job boundary when writing to external APIs, payment systems, queues, or notification systems.

## Troubleshooting

- Bad backend configuration
  Missing gems, invalid adapter setup, or an unset `REDIS_URL` / `DATABASE_URL` will prevent boot. Start by checking `config/kaal.rb` and the adapter-specific README.
- Scheduler file loading issues
  `bundle exec kaal status` and `bundle exec kaal start` load `config/kaal.rb` and then `config/scheduler.yml` relative to the configured root. Confirm both files exist and that `scheduler_config_path` matches your app layout.
- Duplicate job definitions
  Job keys must be unique across the loaded scheduler definition set. Duplicate keys will cause load-time conflicts and must be resolved in `config/scheduler.yml`.
- Backend outages or reconnect issues
  Redis and SQL-backed coordination depend on backend availability. A backend outage means ticks cannot coordinate safely; restore backend health before expecting normal dispatch behavior.
- Guarantee assumptions not met
  If duplicate dispatches appear, verify the shared backend, namespace, dispatch-log registry setting, and lease sizing before assuming a scheduler bug.

## Development

Repo-level entrypoints live under `scripts/`:

```bash
scripts/run-rubocop-all
scripts/run-reek-all
scripts/run-rspec-unit-all
scripts/run-rspec-e2e-all
scripts/run-multi-node-cli-all
```

Or run the full repo-level pass in one command:

```bash
scripts/run-all
```

You can also run checks from an individual package directory, for example:

```bash
cd core/kaal
bin/rspec-unit
bin/rubocop
bin/reek
```

## Documentation and contributing

- Docs site: <https://kaal.codevedas.com>
- Contributor guide: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Security policy: [SECURITY.md](./SECURITY.md)
- Code of conduct: [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

## License

Released under the [MIT License](LICENSE).
