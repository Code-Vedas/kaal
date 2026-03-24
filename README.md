# Kaal

> Distributed cron scheduling for Ruby, split into a core engine plus datastore and framework integration gems.

[![Gem](https://img.shields.io/gem/v/kaal.svg?style=flat-square)](https://rubygems.org/gems/kaal)
[![CI](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)

## Project Structure

```text
/repo-root
├── .github/
├── core/                   # Core engine and datastore gems
│   ├── kaal/.              #   Core engine gem
│   ├── kaal-sequel/        #   Sequel datastore adapter gem
│   └── kaal-activerecord/  #   Active Record datastore adapter gem
├── gems/                   # Framework integration gems
│   ├── kaal-hanami/        #   Hanami plugin gem
│   ├── kaal-rails/         #   Rails plugin gem
│   ├── kaal-roda/          #   Roda plugin gem
│   └── kaal-sinatra/       #   Sinatra plugin gem
├── docs/                   # Documentation source files
├── danger/                 # Danger configuration and plugins
└── README.md
```

## Package Layout

- `core/kaal`
  Core engine gem. Owns runtime coordination, registry contracts, CLI, memory backend, and redis backend.
- `core/kaal-sequel`
  Sequel-backed datastore adapter. Owns SQL persistence, SQL lock adapters, and SQL migrations/templates for Sequel-based installs.
- `core/kaal-activerecord`
  Active Record-backed datastore adapter. Owns Active Record models, registries, SQL lock adapters, and migration templates.
- `gems/kaal-hanami`
  Hanami integration gem. Depends on `kaal` and `kaal-sequel`, and owns middleware-based boot wiring, backend auto-wiring, and the Hanami dummy app.
- `gems/kaal-rails`
  Rails plugin gem. Depends on `kaal` and `kaal-activerecord`, and owns Railtie, generators, tasks, and the Rails dummy app.
- `gems/kaal-roda`
  Roda integration gem. Depends on `kaal` and `kaal-sequel`, and owns plugin registration, backend auto-wiring, and the Roda dummy app.
- `gems/kaal-sinatra`
  Sinatra integration gem. Supports memory, redis, and Sequel-backed SQL through explicit Sinatra boot wiring.

## What Kaal Does

Kaal lets you register recurring jobs and coordinate dispatch across multiple processes or nodes.

For Redis, Postgres, and MySQL-backed deployments, Kaal guarantees at-most-once dispatch per `(key, fire_time)` under the documented crash-and-restart model. The full guarantee, assumptions, and evidence are documented at <https://kaal.codevedas.com/dispatch-guarantee>.

The engine is framework-agnostic. You choose the datastore and framework integration that fits your app.

## Install Surfaces

Use the gem surface that matches your runtime:

- `kaal`
  Plain Ruby with in-process memory coordination or Redis coordination.
- `kaal` + `kaal-sequel`
  Plain Ruby with Sequel-backed SQL persistence.
- `kaal` + `kaal-activerecord`
  Plain Ruby with Active Record-backed SQL persistence.
- `kaal-rails`
  Rails plugin with Active Record auto-wiring, generators, and rake tasks.
- `kaal-hanami`
  Hanami integration with memory, redis, or SQL backends.
- `kaal-roda`
  Roda integration with memory, redis, or SQL backends.
- `kaal-sinatra`
  Sinatra integration with memory, redis, or SQL backends.

Plain Ruby with memory or Redis:

```ruby
gem 'kaal'
```

Plain Ruby with Sequel-backed SQL persistence:

```ruby
gem 'kaal'
gem 'kaal-sequel'
```

Rails with Active Record:

```ruby
gem 'kaal-rails'
```

Hanami with any supported backend:

```ruby
gem 'kaal-hanami'
```

Roda with any supported backend:

```ruby
gem 'kaal-roda'
```

Sinatra with any supported backend:

```ruby
gem 'kaal-sinatra'
```

Plain Ruby with Active Record-backed SQL persistence:

```ruby
gem 'kaal'
gem 'kaal-activerecord'
```

## Usage Paths

Memory:

```ruby
require 'kaal'

Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
  config.scheduler_config_path = 'config/scheduler.yml'
end
```

Redis:

```ruby
require 'kaal'
require 'redis'

redis = Redis.new(url: ENV.fetch('REDIS_URL'))

Kaal.configure do |config|
  config.backend = Kaal::Backend::RedisAdapter.new(redis)
  config.scheduler_config_path = 'config/scheduler.yml'
end
```

Sequel:

```ruby
require 'kaal'
require 'kaal/sequel'
require 'sequel'

database = Sequel.connect(adapter: 'sqlite', database: 'db/kaal.sqlite3')

Kaal.configure do |config|
  config.backend = Kaal::Backend::DatabaseAdapter.new(database)
  config.scheduler_config_path = 'config/scheduler.yml'
end
```

Active Record:

```ruby
require 'kaal'
require 'kaal/active_record'

Kaal::ActiveRecord::ConnectionSupport.configure!(
  adapter: 'sqlite3',
  database: 'db/kaal.sqlite3'
)

Kaal.configure do |config|
  config.backend = Kaal::ActiveRecord::DatabaseAdapter.new
  config.scheduler_config_path = 'config/scheduler.yml'
end
```

Rails:

```ruby
gem 'kaal-rails'
```

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

Sinatra with memory:

```ruby
require 'sinatra/base'
require 'kaal/sinatra'

class App < Sinatra::Base
  register Kaal::Sinatra::Extension

  kaal backend: Kaal::Backend::MemoryAdapter.new,
       scheduler_config_path: 'config/scheduler.yml'
end
```

Hanami with memory:

```ruby
require 'hanami'
require 'kaal/hanami'

module MyApp
  class App < Hanami::App
    Kaal::Hanami.configure!(
      self,
      backend: Kaal::Backend::MemoryAdapter.new,
      scheduler_config_path: 'config/scheduler.yml'
    )
  end
end
```

Roda with memory:

```ruby
require 'roda'
require 'kaal/roda'

class App < Roda
  plugin :kaal

  kaal backend: Kaal::Backend::MemoryAdapter.new,
       scheduler_config_path: 'config/scheduler.yml'

  route do |r|
    r.root { 'ok' }
  end
end
```

Or:

```bash
bundle exec rails generate kaal:install --backend=postgres
bundle exec rails db:migrate
```

```bash
bundle exec rails generate kaal:install --backend=mysql
bundle exec rails db:migrate
```

## Dispatch Guarantee

Kaal's scheduler-side guarantee is:

- at-most-once dispatch per `(key, fire_time)` for Redis, Postgres, and MySQL
- deterministic `idempotency_key` generation for the same `(key, fire_time)`

This guarantee applies when:

- nodes share the same healthy backend
- `enable_log_dispatch_registry = true`
- `lease_ttl >= window_lookback + tick_interval`
- nodes share the same namespace and scheduler definition set

Use the provided `idempotency_key` inside your jobs to make downstream effects effectively once as well.

## Local Development

Run checks from the relevant gem directory.

Examples:

```bash
cd core/kaal
bin/rspec-unit
bin/rubocop
bin/reek
```

```bash
cd core/kaal-sequel
bin/rspec-unit
bin/rspec-e2e sqlite
```

```bash
cd core/kaal-activerecord
bin/rspec-unit
bin/rspec-e2e sqlite
```

```bash
cd gems/kaal-hanami
bin/rspec-unit
bin/rspec-e2e memory
bin/rspec-e2e sqlite
```

```bash
cd gems/kaal-sinatra
bin/rspec-unit
bin/rspec-e2e memory
bin/rspec-e2e sqlite
```

```bash
cd gems/kaal-roda
bin/rspec-unit
bin/rspec-e2e memory
bin/rspec-e2e sqlite
```

## Documentation

Project docs are published at:

<https://kaal.codevedas.com>

Key pages:

- [Overview](https://kaal.codevedas.com/overview)
- [Installation](https://kaal.codevedas.com/install)
- [Configuration](https://kaal.codevedas.com/configuration)
- [Usage](https://kaal.codevedas.com/usage)
- [Dispatch Guarantee](https://kaal.codevedas.com/dispatch-guarantee)

## Contributing

- [CONTRIBUTING.md](./CONTRIBUTING.md)
- [SECURITY.md](./SECURITY.md)
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

## License

Released under the [MIT License](LICENSE).
