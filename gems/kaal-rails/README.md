# Kaal::Rails

Rails plugin gem for Kaal.

`kaal-rails` depends on:

- `kaal`
- `kaal-activerecord`

It owns the Rails integration surface:

- Railtie
- rake tasks
- generators
- Active Record migration generation
- Rails dummy app and Rails-specific test coverage

## Install

```ruby
gem 'kaal-rails'
```

Then generate the scheduler config and migrations:

```bash
bundle exec rails generate kaal:install --backend=sqlite
bundle exec rails db:migrate
```

PostgreSQL:

```bash
bundle exec rails generate kaal:install --backend=postgres
bundle exec rails db:migrate
```

MySQL:

```bash
bundle exec rails generate kaal:install --backend=mysql
bundle exec rails db:migrate
```

## What It Provides

- Rails-native setup on top of the Kaal engine
- Active Record-backed persistence through `kaal-activerecord`
- migration templates for the Kaal tables required by the selected backend
- automatic backend selection from the Rails database adapter unless the app sets `Kaal.configuration.backend` itself

## Usage

Add the gem to your Rails app and configure only if you need overrides:

```ruby
Kaal.configure do |config|
  config.scheduler_config_path = Rails.root.join('config/scheduler.yml')
end
```

If you do nothing, `kaal-rails` will auto-wire:

- SQLite to `Kaal::ActiveRecord::DatabaseAdapter`
- PostgreSQL to `Kaal::ActiveRecord::PostgresAdapter`
- MySQL to `Kaal::ActiveRecord::MySQLAdapter`

Available Rails surfaces:

- `bin/rails generate kaal:install --backend=sqlite`
- `bin/rails generate kaal:install --backend=postgres`
- `bin/rails generate kaal:install --backend=mysql`
- `bin/rake kaal:install:all`
- `bin/rake kaal:install:migrations`

## Development

```bash
bin/rspec-unit
bin/rspec-e2e sqlite
bin/rubocop
bin/reek
```
