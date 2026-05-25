# Kaal

> Distributed cron scheduling for Ruby, centered on one core gem plus framework integration gems.

[![Gem](https://img.shields.io/gem/v/kaal.svg?style=flat-square)](https://rubygems.org/gems/kaal)
[![CI](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)

Kaal coordinates recurring and delayed jobs across processes or nodes without changing how your app enqueues work. You choose the package surface that matches your runtime, configure a backend, use the runtime APIs, and run the scheduler in a dedicated process with `bundle exec kaal start`.

For Redis, Postgres, and MySQL-backed deployments, Kaal guarantees at-most-once dispatch per `(key, fire_time)` for recurring jobs and at-most-once dispatch per `job_id` for delayed jobs under the documented crash-and-restart model. Use the provided `idempotency_key` in your job boundary when downstream effects must also be deduplicated.

Project docs: <https://kaal.codevedas.com>

## Package selection

Choose the gem surface that matches your app:

- `kaal`
  Plain Ruby with memory, Redis, Sequel-backed SQL, or Active Record-backed SQL.
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
│   └── kaal/              # Core engine gem, CLI, memory backend, redis backend, and SQL backends
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

- `config/kaal.yml`
- `config/kaal-scheduler.yml`

Register a recurring job in `config/kaal-scheduler.yml`:

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

`kaal init` only supports `memory` and `redis`. For SQL-backed setups, add the database libraries your app uses, set `backend: sqlite/postgres/mysql` plus `backend_config` in `config/kaal.yml`, or use the framework-specific install surface.

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
gem "sequel"
```

Example `config/kaal.yml`:

```yaml
defaults:
  backend: sqlite
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    url: db/kaal.sqlite3
```

Use `backend: postgres` or `backend: mysql` with `backend_config.url: <%= ENV.fetch("KAAL_BACKEND_URL", ENV.fetch("DATABASE_URL")) %>` for PostgreSQL and MySQL.

Redis example `config/kaal.yml`:

```yaml
defaults:
  backend: redis
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    url: redis://127.0.0.1:6379/0
```

### Plain Ruby with Active Record-backed SQL

```ruby
gem "kaal"
gem "activerecord"
```

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

Use `backend: postgres` or `backend: mysql` with `backend_config.url` or `KAAL_BACKEND_URL` for PostgreSQL and MySQL.

### Rails

```ruby
gem "kaal-rails"
```

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

For PostgreSQL or MySQL, swap `sqlite` for `postgres` or `mysql`.

The generated migrations install the full Kaal persistence surface.

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

  kaal scheduler_config_path: "config/kaal-scheduler.yml",
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

  kaal scheduler_config_path: "config/kaal-scheduler.yml",
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
      scheduler_config_path: "config/kaal-scheduler.yml",
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
[Unit]
Description=Kaal scheduler
After=network.target

[Service]
WorkingDirectory=/srv/my-app/current
ExecStart=/usr/bin/bash -lc 'bundle exec kaal start'
ExecStartPre=/usr/bin/bash -lc 'bundle exec kaal status'
Restart=always

[Install]
WantedBy=multi-user.target
```

Kubernetes:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-scheduler
  labels:
    app: my-app-scheduler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app-scheduler
  template:
    metadata:
      labels:
        app: my-app-scheduler
    spec:
      containers:
        - name: scheduler
          image: my-app:latest
          command: ["bundle", "exec", "kaal", "start"]
```

Framework integrations can start the scheduler inside the web process, but that should be an intentional opt-in, not the default production model.

## Runtime API

Recurring jobs:

```ruby
Kaal.register(
  key: "reports:daily",
  cron: "0 9 * * *",
  enqueue: ->(fire_time:, idempotency_key:) {
    ReportsJob.perform(fire_time: fire_time, idempotency_key: idempotency_key)
  }
)
```

Delayed jobs:

```ruby
Kaal.enqueue_at(
  at: Time.now.utc + 300,
  job_class: "BillingReminderJob",
  args: [invoice_id],
  queue: "mailers",
  job_id: "billing-reminder:#{invoice_id}"
)
```

Both surfaces share the same backend and dispatch model. Delayed jobs require unique `job_id` values while pending, use positional `args`, and follow the same job-class resolution rules: string names are constantized and class or module values are used directly.

Restrict delayed-job class names when needed:

```ruby
Kaal.configure do |config|
  config.delayed_job_allowed_class_prefixes = ["Reports::", "Billing::"]
end
```

Leave `delayed_job_allowed_class_prefixes` empty only for local or otherwise trusted deployments. On shared Redis or SQL backends in production, Kaal will warn because delayed jobs resolve stored `job_class` values at dispatch time.

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
  Missing gems, invalid adapter setup, or an unset `KAAL_BACKEND_URL` / `REDIS_URL` / `DATABASE_URL` will prevent boot. Start by checking `config/kaal.yml` and the adapter-specific README.
- Scheduler file loading issues
  `bundle exec kaal status` and `bundle exec kaal start` load `config/kaal.yml` and then `config/kaal-scheduler.yml` relative to the configured root. Confirm both files exist and that `scheduler_config_path` matches your app layout.
- Duplicate job definitions
  Job keys must be unique across the loaded scheduler definition set. Duplicate keys will cause load-time conflicts and must be resolved in `config/kaal-scheduler.yml`.
- Backend outages or reconnect issues
  Redis and SQL-backed coordination depend on backend availability. A backend outage means ticks cannot coordinate safely; restore backend health before expecting normal dispatch behavior.
- Guarantee assumptions not met
  If duplicate dispatches appear, verify the shared backend, namespace, dispatch-log registry setting, and lease sizing before assuming a scheduler bug.

## Development

Repo-level entrypoints live under `scripts/`:

```bash
scripts/run-rubocop-all
scripts/run-reek-all
scripts/run-rbs-all
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
cd gems/kaal
bin/rspec-unit
bin/rubocop
bin/reek
rbs -I sig validate
```

## Documentation and contributing

- Docs site: <https://kaal.codevedas.com>
- Contributor guide: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Security policy: [SECURITY.md](./SECURITY.md)
- Code of conduct: [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

## License

Released under the [MIT License](LICENSE).
