---
title: Usage
nav_order: 5
permalink: /usage
---

# Usage

For the exact multi-node claim, assumptions, and evidence, see [At-Most-Once Dispatch Guarantee](/dispatch-guarantee).

## Register recurring jobs

Define jobs in `config/scheduler.yml`:

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

Kaal loads the scheduler file at boot and dispatches the configured work on each eligible tick.

For Redis, Postgres, and MySQL-backed deployments, the same `(key, fire_time)` yields the same deterministic `idempotency_key`. Use that key at the job boundary when downstream systems also need dedupe.

## Configure the backend

The registration model stays the same across adapters. What changes is the configured backend.

### Plain Ruby with memory

```ruby
require "kaal"

Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
  config.scheduler_config_path = "config/scheduler.yml"
end
```

### Plain Ruby with Redis

```ruby
require "kaal"
require "redis"

redis = Redis.new(url: ENV.fetch("REDIS_URL"))

Kaal.configure do |config|
  config.backend = Kaal::Backend::RedisAdapter.new(redis)
  config.scheduler_config_path = "config/scheduler.yml"
end
```

### Plain Ruby with Sequel-backed SQL

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

For PostgreSQL or MySQL, use one of:

```ruby
config.backend = Kaal::Backend::PostgresAdapter.new(database)
```

```ruby
config.backend = Kaal::Backend::MySQLAdapter.new(database)
```

### Plain Ruby with Active Record-backed SQL

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

For PostgreSQL or MySQL, use one of:

```ruby
config.backend = Kaal::ActiveRecord::PostgresAdapter.new
```

```ruby
config.backend = Kaal::ActiveRecord::MySQLAdapter.new
```

### Rails

```ruby
gem "kaal-rails"
```

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

Rails auto-selects the Active Record-backed adapter from the configured database unless you override `Kaal.configuration.backend` yourself.

### Sinatra

Memory:

```ruby
require "sinatra/base"
require "kaal/sinatra"

class App < Sinatra::Base
  register Kaal::Sinatra::Extension

  kaal backend: Kaal::Backend::MemoryAdapter.new,
       scheduler_config_path: "config/scheduler.yml",
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
  REDIS = Redis.new(url: ENV.fetch("REDIS_URL"))

  register Kaal::Sinatra::Extension

  kaal redis: REDIS,
       scheduler_config_path: "config/scheduler.yml",
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
       scheduler_config_path: "config/scheduler.yml",
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

  kaal backend: Kaal::Backend::MemoryAdapter.new,
       scheduler_config_path: "config/scheduler.yml",
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
  REDIS = Redis.new(url: ENV.fetch("REDIS_URL"))

  plugin :kaal

  kaal redis: REDIS,
       scheduler_config_path: "config/scheduler.yml",
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
       scheduler_config_path: "config/scheduler.yml",
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
      backend: Kaal::Backend::MemoryAdapter.new,
      scheduler_config_path: "config/scheduler.yml",
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
    REDIS = Redis.new(url: ENV.fetch("REDIS_URL"))

    Kaal::Hanami.configure!(
      self,
      redis: REDIS,
      scheduler_config_path: "config/scheduler.yml",
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
      scheduler_config_path: "config/scheduler.yml",
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
