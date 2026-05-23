# Kaal

Distributed cron scheduling for plain Ruby.

`kaal` is the core engine gem. It owns scheduler/runtime behavior, the registry APIs, the plain Ruby CLI, delayed-job dispatch, and the optional SQL backend surfaces.

## Installation

Use `kaal` by itself when you want the engine plus non-SQL coordination backends.

```ruby
gem 'kaal'
```

Then install and initialize:

```bash
bundle install
bundle exec kaal init --backend=memory
```

`kaal init` creates:

- `config/kaal.rb`
- `config/scheduler.yml`

Supported backends:

- `memory`
- `redis`

If you want SQL persistence instead, add the runtime libraries your app uses, such as `sequel`, `activerecord`, `sqlite3`, `pg`, or `mysql2`, then configure one of the explicit `Kaal::Backend::*` SQL backends.

## Configuration

Generated `config/kaal.rb` is the primary entrypoint:

```ruby
require 'kaal'

Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
  config.tick_interval = 5
  config.window_lookback = 120
  config.lease_ttl = 125
  config.scheduler_config_path = 'config/scheduler.yml'
end
```

Redis path:

```ruby
require 'redis'

redis = Redis.new(url: ENV.fetch('REDIS_URL'))

Kaal.configure do |config|
  config.backend = Kaal::Backend::RedisAdapter.new(redis)
  config.scheduler_config_path = 'config/scheduler.yml'
end
```

Time zone behavior is explicit:

- use `config.time_zone = 'America/Toronto'` when needed
- otherwise scheduling runs in `UTC`

## Scheduler File

Default scheduler definitions live at `config/scheduler.yml`:

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

`job_class` must resolve to a Ruby constant that responds to one of:

- `.perform(*args, **kwargs)`
- `.perform_later(*args, **kwargs)`
- `.set(queue: ...).perform_later(*args, **kwargs)`

For plain Ruby `.perform` jobs, Kaal treats the dispatch as successful unless the job raises an exception. Return values are ignored.

## CLI

```bash
bundle exec kaal init --backend=memory
bundle exec kaal start
bundle exec kaal status
bundle exec kaal tick
bundle exec kaal explain "*/15 * * * *"
bundle exec kaal next "0 9 * * 1" --count 3
```

## E2E Verification

```bash
bin/rspec-e2e memory
REDIS_URL=redis://127.0.0.1:6379/0 bin/rspec-e2e redis
```

## Runtime API

Recurring jobs:

```ruby
Kaal.register(
  key: 'reports:daily',
  cron: '0 9 * * *',
  enqueue: ->(fire_time:, idempotency_key:) {
    ReportsJob.perform(fire_time: fire_time, idempotency_key: idempotency_key)
  }
)

Kaal.start!
```

Delayed jobs:

```ruby
Kaal.enqueue_at(
  at: Time.now.utc + 300,
  job_class: "InvoiceReminderJob",
  args: [123],
  queue: "mailers",
  job_id: "invoice-reminder:123"
)
```

Rules shared by the runtime surface:

- delayed jobs use `job_id` as their identity and require it to be unique while pending
- delayed-job `args` are positional only
- recurring and delayed jobs share the same job-class dispatch rules
- string job classes are constantized and class or module values are used directly

To restrict delayed-job class names:

```ruby
Kaal.configure do |config|
  config.delayed_job_allowed_class_prefixes = ["Reports::", "Billing::"]
end
```

An empty `delayed_job_allowed_class_prefixes` list leaves delayed-job class resolution unrestricted. That is reasonable for local or trusted deployments. On shared Redis or SQL backends in production, set a restrictive prefix list.

## SQL Backends

Use the explicit SQL backends when you want persisted registries:

- `Kaal::Backend::SQLite`
- `Kaal::Backend::Postgres`
- `Kaal::Backend::MySQL`
- `kaal-rails` for Rails-native install and auto-wiring

For SQL-backed deployments, run the generated migrations so `kaal_delayed_jobs` exists alongside the recurring scheduler tables.

Postgres and supported MySQL versions claim due delayed jobs with `SKIP LOCKED`. Older SQL paths still preserve correctness with delete confirmation, and Kaal adds a small pre-claim jitter there to reduce multi-node contention.
