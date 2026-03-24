---
layout: default
title: Home
nav_order: 1
---

# Kaal

> Until V1, Kaal is in early development and should not be used in production environments. We welcome contributions and feedback to help shape the future of Kaal!

Kaal is a distributed cron scheduler for Ruby that safely executes scheduled tasks across multiple nodes.

![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
[![Gem Version](https://img.shields.io/gem/v/kaal?style=flat-square&logo=rubygems&label=kaal)](https://rubygems.org/gems/kaal){:target="_blank"}
[![Gem Version](https://img.shields.io/gem/v/kaal-sequel?style=flat-square&logo=rubygems&label=kaal-sequel)](https://rubygems.org/gems/kaal-sequel){:target="_blank"}
[![Gem Version](https://img.shields.io/gem/v/kaal-activerecord?style=flat-square&logo=rubygems&label=kaal-activerecord)](https://rubygems.org/gems/kaal-activerecord){:target="_blank"}
[![Gem Version](https://img.shields.io/gem/v/kaal-hanami?style=flat-square&logo=rubygems&label=kaal-hanami)](https://rubygems.org/gems/kaal-hanami){:target="_blank"}
[![Gem Version](https://img.shields.io/gem/v/kaal-rails?style=flat-square&logo=rubygems&label=kaal-rails)](https://rubygems.org/gems/kaal-rails){:target="_blank"}
[![Gem Version](https://img.shields.io/gem/v/kaal-roda?style=flat-square&logo=rubygems&label=kaal-roda)](https://rubygems.org/gems/kaal-roda){:target="_blank"}
[![Gem Version](https://img.shields.io/gem/v/kaal-sinatra?style=flat-square&logo=rubygems&label=kaal-sinatra)](https://rubygems.org/gems/kaal-sinatra){:target="_blank"}
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)

- 📦 monorepo:
  - [`core/kaal/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal)
  - [`core/kaal-sequel/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal-sequel)
  - [`core/kaal-activerecord/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal-activerecord)
  - [`gems/kaal-hanami/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-hanami)
  - [`gems/kaal-rails/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-rails)
  - [`gems/kaal-roda/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-roda)
  - [`gems/kaal-sinatra/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-sinatra)

---

## Install the right package

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

```bash
bundle install
bundle exec kaal init --backend=memory
```

## Links

- [Installation & Setup](./install) for package selection and installation.
- [Configuration Options](./configuration) for runtime configuration.
- [Usage & Examples](./usage) for registration, runtime, and process layout.
- [At-Most-Once Dispatch Guarantee](./dispatch-guarantee) for the exact scheduler-side guarantee, assumptions, and evidence.
- [FAQ / Troubleshooting](./faq) for common questions and fixes.

## Features

- **Scheduler-agnostic**: Works with any job system (`ActiveJob`, `Sidekiq`, `Resque`, etc.)
- **Documented dispatch guarantee**: At-most-once dispatch per `(key, fire_time)` under the documented crash-and-restart model
- **Split packages**: engine, datastore adapters, and framework integrations are shipped separately
- **Backend adapters**: memory and Redis live in core; SQL persistence lives in `kaal-sequel` or `kaal-activerecord`
- **Framework addons**: `kaal-hanami` for Hanami, `kaal-rails` for Rails, `kaal-roda` for Roda, and `kaal-sinatra` for Sinatra
- **Registry & API**: Centralized job registration with deterministic idempotency keys for downstream dedupe
- **Dispatch recovery**: Replays missed runs within a configurable lookback window
- **Cron utilities**: Validate, lint, simplify, and humanize via `Kaal.valid?`, `Kaal.lint`, `Kaal.simplify`, and `Kaal.to_human`
- **i18n keys**: Fully localizable weekdays, months, and time phrases (`kaal.*`)
- **CLI tools**: `kaal init`, `start`, `status`, `tick`, `explain`, and `next`
- **Standalone mode**: Launch scheduler via Procfile, systemd, or Kubernetes
- **Observability**: Optional status inspection via `kaal status`
- **Graceful shutdown**: Handles `TERM`/`INT` signals and finishes current tick cleanly
- **Testing**: Thread-safe, multi-node safety specs included
- **Development & CI**: Bundler, RSpec, RuboCop, GitHub Actions workflows
- **Documentation**: README, feature templates, and roadmap included

---

## Professional support

Need help with integrating or customizing `kaal` for your project? We offer professional support and custom development services. Contact us at [sales@codevedas.com](mailto:sales@codevedas.com) for inquiries.

## License

Copyright (c) 2025-present Codevedas Inc. and the Kaal Authors
