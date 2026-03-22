---
title: Usage
nav_order: 5
permalink: /usage
---

# Usage

Register recurring jobs in Ruby:

```ruby
Kaal.register(
  key: "reports:weekly_summary",
  cron: "0 9 * * 1",
  enqueue: ->(fire_time:, idempotency_key:) {
    WeeklySummaryJob.perform(fire_time: fire_time, idempotency_key: idempotency_key)
  }
)
```

The engine API stays the same across datastore adapters. What changes is the configured backend.

## Usage Paths

### Plain Ruby with memory

Use `kaal` only:

```ruby
require "kaal"

Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
  config.scheduler_config_path = "config/scheduler.yml"
end
```

### Plain Ruby with Redis

Use `kaal` only:

```ruby
require "kaal"
require "redis"

Kaal.configure do |config|
  redis = Redis.new(url: ENV.fetch("REDIS_URL"))
  config.backend = Kaal::Backend::RedisAdapter.new(redis)
  config.scheduler_config_path = "config/scheduler.yml"
end
```

### Plain Ruby with Sequel SQL

Use `kaal` plus `kaal-sequel`:

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

Swap the adapter class when using PostgreSQL or MySQL:

```ruby
config.backend = Kaal::Backend::PostgresAdapter.new(database)
config.backend = Kaal::Backend::MySQLAdapter.new(database)
```

### Plain Ruby with Active Record SQL

Use `kaal` plus `kaal-activerecord`:

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

For PostgreSQL or MySQL:

```ruby
config.backend = Kaal::ActiveRecord::PostgresAdapter.new
config.backend = Kaal::ActiveRecord::MySQLAdapter.new
```

### Rails

Use `kaal-rails`:

```ruby
gem "kaal-rails"
```

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

```bash
bundle exec rails generate kaal:install --backend=postgres
bundle exec rails db:migrate
```

```bash
bundle exec rails generate kaal:install --backend=mysql
bundle exec rails db:migrate
```

In Rails, the backend is auto-selected from the configured database adapter unless you explicitly override it.

### Sinatra

Use `kaal-sinatra` with the backend style you want.

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
  redis = Redis.new(url: ENV.fetch("REDIS_URL"))

  register Kaal::Sinatra::Extension

  kaal redis: redis,
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

For classic Sinatra apps, use explicit registration:

```ruby
require "sinatra"
require "sequel"
require "kaal/sinatra"

database = Sequel.connect(ENV.fetch("DATABASE_URL"))

Kaal::Sinatra.register!(
  settings,
  database: database,
  scheduler_config_path: "config/scheduler.yml",
  namespace: "my-app",
  start_scheduler: false
)
```

`kaal-sinatra` loads `config/scheduler.yml` relative to the Sinatra app root and only starts the scheduler if you opt in.

## CLI

```bash
bundle exec kaal init --backend=memory
bundle exec kaal start
bundle exec kaal status
bundle exec kaal tick
bundle exec kaal explain "*/15 * * * *"
bundle exec kaal next "0 9 * * 1" --count 3
```

## Production Runtime

Use a dedicated scheduler process:

```procfile
web: bundle exec puma -C config/puma.rb
scheduler: bundle exec kaal start
```

```ini
ExecStart=/usr/bin/bash -lc 'bundle exec kaal start'
ExecStartPre=/usr/bin/bash -lc 'bundle exec kaal status'
```

## Adapter Notes

- Use `kaal` by itself for memory or redis-backed scheduling.
- Use `kaal-sequel` for Sequel-backed SQL persistence in plain Ruby apps.
- Use `kaal-activerecord` for Active Record-backed SQL persistence in plain Ruby apps.
- Use `kaal-rails` for Rails apps; it pulls in `kaal-activerecord` and provides Rails-native integration.
- Use `kaal-sinatra` for Sinatra apps; it provides explicit Sinatra boot and lifecycle wiring across memory, redis, and SQL backends.

For plain Ruby jobs dispatched through `.perform(*args, **kwargs)`, Kaal considers the run successful unless the job raises. Return values are not inspected.
