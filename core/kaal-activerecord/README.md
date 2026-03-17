# Kaal::ActiveRecord

Active Record-backed datastore adapter for Kaal.

`kaal-activerecord` depends on `kaal` and owns the Active Record persistence layer:

- Active Record models for Kaal tables
- Active Record-backed definition registry
- Active Record-backed dispatch registry
- SQLite table-lock adapter
- PostgreSQL advisory-lock adapter
- MySQL named-lock adapter
- Rails-friendly migration templates

## Install

Plain Ruby:

```ruby
gem 'kaal'
gem 'kaal-activerecord'
```

Rails applications normally use `kaal-rails`, which already depends on this gem.

## Usage

SQLite in plain Ruby:

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

PostgreSQL in plain Ruby:

```ruby
config.backend = Kaal::ActiveRecord::PostgresAdapter.new
```

MySQL in plain Ruby:

```ruby
config.backend = Kaal::ActiveRecord::MySQLAdapter.new
```

Use this gem directly when you want Active Record-backed SQL outside Rails. For Rails apps, use `kaal-rails`.

## Tables

The Active Record adapter persists against:

- `kaal_definitions`
- `kaal_dispatches`
- `kaal_locks`

`kaal_locks` is used for SQLite. PostgreSQL and MySQL rely on advisory or named locks and persist definitions and dispatches without a dedicated locks table.

## Development

```bash
bin/rspec-unit
bin/rspec-e2e sqlite
bin/rubocop
bin/reek
```
