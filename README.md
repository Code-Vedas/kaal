# Kaal

> Distributed cron scheduling for Ruby, split into a core engine plus datastore and framework integration gems.

[![Gem](https://img.shields.io/gem/v/kaal.svg?style=flat-square)](https://rubygems.org/gems/kaal)
[![CI core/kaal](https://github.com/Code-Vedas/kaal/actions/workflows/ci-kaal.yml/badge.svg)](https://github.com/Code-Vedas/kaal/actions/workflows/ci-kaal.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)

## Project Structure

```text
/repo-root
├── .github/
├── core/
│   ├── kaal/
│   ├── kaal-sequel/
│   └── kaal-activerecord/
├── gems/
│   └── kaal-rails/
├── docs/
└── README.md
```

## Package Layout

- `core/kaal`
  Core engine gem. Owns runtime coordination, registry contracts, CLI, memory backend, and redis backend.
- `core/kaal-sequel`
  Sequel-backed datastore adapter. Owns SQL persistence, SQL lock adapters, and SQL migrations/templates for Sequel-based installs.
- `core/kaal-activerecord`
  Active Record-backed datastore adapter. Owns Active Record models, registries, SQL lock adapters, and migration templates.
- `gems/kaal-rails`
  Rails plugin gem. Depends on `kaal` and `kaal-activerecord`, and owns Railtie, generators, tasks, and the Rails dummy app.

## What Kaal Does

Kaal lets you register recurring jobs and coordinate dispatch across multiple processes or nodes without duplicate execution for a given cron fire time.

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

Or:

```bash
bundle exec rails generate kaal:install --backend=postgres
bundle exec rails db:migrate
```

```bash
bundle exec rails generate kaal:install --backend=mysql
bundle exec rails db:migrate
```

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

## Documentation

Project docs are published at:

<https://kaal.codevedas.com>

Key pages:

- [Overview](https://kaal.codevedas.com/overview)
- [Installation](https://kaal.codevedas.com/install)
- [Configuration](https://kaal.codevedas.com/configuration)
- [Usage](https://kaal.codevedas.com/usage)

## Contributing

- [CONTRIBUTING.md](./CONTRIBUTING.md)
- [SECURITY.md](./SECURITY.md)
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

## License

Released under the [MIT License](LICENSE).
