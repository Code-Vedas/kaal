# Kaal::Sequel

Sequel-backed datastore adapter for Kaal.

`kaal-sequel` depends on `kaal` and owns the Sequel persistence layer:

- Sequel-backed definition registry
- Sequel-backed dispatch registry
- SQLite table-lock adapter
- PostgreSQL advisory-lock adapter
- MySQL named-lock adapter
- Sequel migration templates for Kaal tables

## Install

```ruby
gem 'kaal'
gem 'kaal-sequel'
```

## Usage

SQLite:

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

PostgreSQL:

```ruby
config.backend = Kaal::Backend::PostgresAdapter.new(database)
```

MySQL:

```ruby
config.backend = Kaal::Backend::MySQLAdapter.new(database)
```

This is the plain Ruby SQL path when you want Sequel to own the tables, registries, and lock adapters without Rails.

## Tables

The Sequel adapter persists against:

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
