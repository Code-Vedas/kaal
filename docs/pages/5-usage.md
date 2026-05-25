---
title: Usage
nav_order: 5
permalink: /usage
---

# Usage

For the exact multi-node claim, assumptions, and evidence, see [At-Most-Once Dispatch Guarantee](/dispatch-guarantee).

## Register recurring jobs

Define jobs in `config/kaal-scheduler.yml`:

```yaml
defaults:
  jobs:
    - key: "reports:weekly_summary"
      cron: "0 9 * * 1"
      job_class: "WeeklySummaryJob"
      enabled: true
      kwargs:
        idempotency_key: "{{idempotency_key}}"
```

Kaal loads the scheduler file at boot and dispatches the configured recurring work on each eligible tick.

For Redis, Postgres, and MySQL-backed deployments, the same `(key, fire_time)` yields the same deterministic `idempotency_key`. Use that key at the job boundary when downstream systems also need dedupe.

## Runtime API

Recurring jobs come from `config/kaal-scheduler.yml`. Delayed jobs use `Kaal.enqueue_at`:

```ruby
Kaal.enqueue_at(
  at: Time.now.utc + 300,
  job_class: "ReminderJob",
  args: [user_id],
  queue: "mailers",
  job_id: "reminder:#{user_id}"
)
```

Delayed-job behavior:

- recurring schedules are defined in `config/kaal-scheduler.yml`; delayed jobs are enqueued directly through the runtime API
- `job_id` is the delayed-job identity and must be unique while the job is pending
- `args` are positional only
- `queue` uses the same dispatch rules as recurring jobs
- string job classes are constantized and class or module values are used directly

## Configure the backend

The registration model stays the same across adapters. What changes is `config/kaal.yml`.

### Plain Ruby with memory

```yaml
defaults:
  backend: memory
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config: {}
```

### Plain Ruby with Redis

```yaml
defaults:
  backend: redis
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    url: redis://127.0.0.1:6379/0
```

### Plain Ruby with Sequel-backed SQL

```yaml
defaults:
  backend: sqlite
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    url: db/kaal.sqlite3
```

For PostgreSQL or MySQL, replace `backend: sqlite` with `backend: postgres` or `backend: mysql`, and set `backend_config.url`.

### Plain Ruby with Active Record-backed SQL

```yaml
defaults:
  backend: sqlite
  scheduler_config_path: config/kaal-scheduler.yml
  backend_config:
    connection:
      adapter: sqlite3
      database: db/kaal.sqlite3
```

For PostgreSQL or MySQL, replace `backend: sqlite` with `backend: postgres` or `backend: mysql`, and set `backend_config.url` or `KAAL_BACKEND_URL`.

### Rails

```ruby
gem "kaal-rails"
```

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

Rails installs `config/kaal.yml` and auto-selects the matching backend from the configured database when `backend` is omitted from that file.

When using delayed jobs in Rails, run the generated Kaal migrations before enqueueing or dispatching work.

Delayed-job class resolution follows one rule everywhere in Kaal:

- string `job_class` values are constantized at dispatch time
- class or module values are used directly when you call `Kaal.enqueue_at`

If your deployment uses a shared Redis or SQL backend in production, configure `delayed_job_allowed_class_prefixes` so stored delayed-job payloads cannot resolve arbitrary application constants.

### Sinatra

Memory:

```ruby
require "sinatra/base"
require "kaal/sinatra"

class App < Sinatra::Base
  register Kaal::Sinatra::Extension

  kaal scheduler_config_path: "config/kaal-scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

Redis:

```ruby
require "sinatra/base"
require "redis"
require "kaal/sinatra"

class App < Sinatra::Base
  REDIS = Redis.new(url: "redis://127.0.0.1:6379/0")

  register Kaal::Sinatra::Extension

  kaal redis: REDIS,
       scheduler_config_path: "config/kaal-scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

SQL:

```ruby
require "sinatra/base"
require "sequel"
require "kaal/sinatra"

class App < Sinatra::Base
  database = Sequel.connect(ENV.fetch("DATABASE_URL"))

  register Kaal::Sinatra::Extension

  kaal database: database,
       adapter: "postgres",
       scheduler_config_path: "config/kaal-scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

### Roda

Memory:

```ruby
require "roda"
require "kaal/roda"

class App < Roda
  plugin :kaal

  kaal scheduler_config_path: "config/kaal-scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

Redis:

```ruby
require "roda"
require "redis"
require "kaal/roda"

class App < Roda
  REDIS = Redis.new(url: "redis://127.0.0.1:6379/0")

  plugin :kaal

  kaal redis: REDIS,
       scheduler_config_path: "config/kaal-scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

SQL:

```ruby
require "roda"
require "sequel"
require "kaal/roda"

database = Sequel.connect(ENV.fetch("DATABASE_URL"))

class App < Roda
  plugin :kaal

  kaal database: database,
       adapter: "postgres",
       scheduler_config_path: "config/kaal-scheduler.yml",
       namespace: "my-app",
       start_scheduler: false
end
```

### Hanami

Memory:

```ruby
require "hanami"
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

Redis:

```ruby
require "hanami"
require "redis"
require "kaal/hanami"

module MyApp
  class App < Hanami::App
    REDIS = Redis.new(url: "redis://127.0.0.1:6379/0")

    Kaal::Hanami.configure!(
      self,
      redis: REDIS,
      scheduler_config_path: "config/kaal-scheduler.yml",
      namespace: "my-app",
      start_scheduler: false
    )
  end
end
```

SQL:

```ruby
require "hanami"
require "sequel"
require "kaal/hanami"

database = Sequel.connect(ENV.fetch("DATABASE_URL"))

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(
      self,
      database: database,
      adapter: "postgres",
      scheduler_config_path: "config/kaal-scheduler.yml",
      namespace: "my-app",
      start_scheduler: false
    )
  end
end
```

## CLI

Available plain-Ruby CLI commands:

```bash
bundle exec kaal init --backend=memory
bundle exec kaal init --backend=redis
bundle exec kaal start
bundle exec kaal status
bundle exec kaal tick
bundle exec kaal explain "*/15 * * * *"
bundle exec kaal next "0 9 * * 1" --count 3
```

`kaal init` does not provision SQL adapter setups. For SQL-backed installs, configure the adapter gem yourself or use the framework-specific install surface.

## Production runtime

Use a dedicated scheduler process when possible.

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

Framework integrations can co-locate the scheduler inside the web process, but that should be an explicit decision, not the default deployment model.

## Operational checks

- `bundle exec kaal status`
  Show current runtime settings and registered jobs.
- `bundle exec kaal tick`
  Run a single scheduler tick for smoke-checking a configured environment.
- `bundle exec kaal explain "CRON"`
  Humanize a cron expression.
- `bundle exec kaal next "CRON" --count N`
  Print upcoming fire times.

For plain Ruby jobs dispatched through `.perform(*args, **kwargs)`, Kaal considers the run successful unless the job raises.
