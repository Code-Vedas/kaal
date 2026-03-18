# Kaal

Distributed cron scheduling for plain Ruby.

`kaal` is the core engine gem. It owns scheduler/runtime behavior, the registry APIs, and the plain Ruby CLI. SQL persistence lives in adapter gems such as `kaal-sequel` and `kaal-activerecord`.

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

If you want SQL persistence instead, add one of:

- `kaal-sequel` for Sequel-backed SQL in plain Ruby
- `kaal-activerecord` for Active Record-backed SQL in plain Ruby
- `kaal-rails` for Rails

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

## Adapter Gems

Use adapter gems when you want persisted SQL registries:

- `kaal-sequel` for Sequel-backed persistence
- `kaal-activerecord` for Active Record-backed persistence
- `kaal-rails` for Rails plugin integration over `kaal-activerecord`
