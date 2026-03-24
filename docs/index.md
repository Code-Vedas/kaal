---
layout: default
title: Home
nav_order: 1
---

# Kaal

Kaal is a distributed cron scheduler for Ruby, packaged as a core engine plus datastore and framework integration gems.

![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
<a href="https://rubygems.org/gems/kaal" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/gem/v/kaal?style=flat-square&logo=rubygems&label=kaal" alt="Gem Version" /></a>
<a href="https://rubygems.org/gems/kaal-sequel" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/gem/v/kaal-sequel?style=flat-square&logo=rubygems&label=kaal-sequel" alt="Gem Version" /></a>
<a href="https://rubygems.org/gems/kaal-activerecord" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/gem/v/kaal-activerecord?style=flat-square&logo=rubygems&label=kaal-activerecord" alt="Gem Version" /></a>
<a href="https://rubygems.org/gems/kaal-hanami" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/gem/v/kaal-hanami?style=flat-square&logo=rubygems&label=kaal-hanami" alt="Gem Version" /></a>
<a href="https://rubygems.org/gems/kaal-rails" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/gem/v/kaal-rails?style=flat-square&logo=rubygems&label=kaal-rails" alt="Gem Version" /></a>
<a href="https://rubygems.org/gems/kaal-roda" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/gem/v/kaal-roda?style=flat-square&logo=rubygems&label=kaal-roda" alt="Gem Version" /></a>
<a href="https://rubygems.org/gems/kaal-sinatra" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/gem/v/kaal-sinatra?style=flat-square&logo=rubygems&label=kaal-sinatra" alt="Gem Version" /></a>
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)

Kaal coordinates recurring jobs across processes or nodes without changing how your app enqueues work. For Redis, Postgres, and MySQL-backed deployments, it guarantees at-most-once dispatch per `(key, fire_time)` under the documented crash-and-restart model.

## Install the right package

- `kaal`
  Plain Ruby with `memory` or `redis`.
- `kaal` + `kaal-sequel`
  Plain Ruby with Sequel-backed SQL persistence.
- `kaal` + `kaal-activerecord`
  Plain Ruby with Active Record-backed SQL persistence.
- `kaal-rails`
  Rails with generators, rake tasks, and Active Record-backed persistence.
- `kaal-hanami`
  Hanami integration across memory, Redis, and Sequel-backed SQL.
- `kaal-roda`
  Roda integration across memory, Redis, and Sequel-backed SQL.
- `kaal-sinatra`
  Sinatra integration across memory, Redis, and Sequel-backed SQL.

Quick start for plain Ruby with memory:

```ruby
gem "kaal"
```

```bash
bundle install
bundle exec kaal init --backend=memory
bundle exec kaal start
```

`kaal init` currently supports `memory` and `redis` only.

## Common commands

```bash
bundle exec kaal status
bundle exec kaal tick
bundle exec kaal explain "*/15 * * * *"
bundle exec kaal next "0 9 * * 1" --count 3
```

## Production model

Run the scheduler in a dedicated process when possible.

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
ExecStart=/usr/bin/bash -lc 'bundle exec kaal start'
ExecStartPre=/usr/bin/bash -lc 'bundle exec kaal status'

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

## Links

- [Overview & Motivation](./overview)
- [Installation & Setup](./install)
- [Configuration](./configuration)
- [Usage](./usage)
- [At-Most-Once Dispatch Guarantee](./dispatch-guarantee)
- [Idempotency Guidance](./idempotency-best-practices)
- [FAQ / Troubleshooting](./faq)
- [Become a contributor](./contribute)

## Monorepo

- [`core/kaal/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal)
- [`core/kaal-sequel/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal-sequel)
- [`core/kaal-activerecord/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal-activerecord)
- [`gems/kaal-hanami/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-hanami)
- [`gems/kaal-rails/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-rails)
- [`gems/kaal-roda/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-roda)
- [`gems/kaal-sinatra/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-sinatra)
