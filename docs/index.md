---
layout: default
title: Home
nav_order: 1
---

# Kaal

{: .note }

> Kaal is in early development until v1.0.0. Expect breaking changes, and please reach out if you'd like to help or have feedback!

Kaal is a distributed cron scheduler for Ruby — a core engine plus datastore and framework integration gems that coordinates recurring jobs across processes or nodes without changing how your app enqueues work. For Redis, Postgres, and MySQL-backed deployments, it guarantees at-most-once dispatch per `(key, fire_time)` under the documented crash-and-restart model.

## Install the right package

- `kaal`
  Plain Ruby with `memory` or `redis`.
- `kaal-sequel`
  Plain Ruby with Sequel-backed SQL persistence.
- `kaal-activerecord`
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

|                                                                     Name                                                                      |                                                                                                        Gem                                                                                                         |                                                                                   RubyDocs                                                                                   |
| :-------------------------------------------------------------------------------------------------------------------------------------------: | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------: |
|              [`core/kaal/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal){:target="\_blank" rel="noopener noreferrer"}              |                    [![Gem Version](https://img.shields.io/gem/v/kaal?style=flat-square&logo=rubygems&label=kaal)](https://rubygems.org/gems/kaal){:target="\_blank" rel="noopener noreferrer"}                     |              [![RubyDoc](https://img.shields.io/badge/rubydoc-kaal-blue.svg)](https://www.rubydoc.info/gems/kaal){:target="\_blank" rel="noopener noreferrer"}               |
|       [`core/kaal-sequel/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal-sequel){:target="\_blank" rel="noopener noreferrer"}       |          [![Gem Version](https://img.shields.io/gem/v/kaal-sequel?style=flat-square&logo=rubygems&label=kaal-sequel)](https://rubygems.org/gems/kaal-sequel){:target="\_blank" rel="noopener noreferrer"}          |       [![RubyDoc](https://img.shields.io/badge/rubydoc-kaal--sequel-blue.svg)](https://www.rubydoc.info/gems/kaal-sequel){:target="\_blank" rel="noopener noreferrer"}       |
| [`core/kaal-activerecord/`](https://github.com/Code-Vedas/kaal/tree/main/core/kaal-activerecord){:target="\_blank" rel="noopener noreferrer"} | [![Gem Version](https://img.shields.io/gem/v/kaal-activerecord?style=flat-square&logo=rubygems&label=kaal-activerecord)](https://rubygems.org/gems/kaal-activerecord){:target="\_blank" rel="noopener noreferrer"} | [![RubyDoc](https://img.shields.io/badge/rubydoc-kaal--activerecord-blue.svg)](https://www.rubydoc.info/gems/kaal-activerecord){:target="\_blank" rel="noopener noreferrer"} |
|       [`gems/kaal-hanami/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-hanami){:target="\_blank" rel="noopener noreferrer"}       |          [![Gem Version](https://img.shields.io/gem/v/kaal-hanami?style=flat-square&logo=rubygems&label=kaal-hanami)](https://rubygems.org/gems/kaal-hanami){:target="\_blank" rel="noopener noreferrer"}          |       [![RubyDoc](https://img.shields.io/badge/rubydoc-kaal--hanami-blue.svg)](https://www.rubydoc.info/gems/kaal-hanami){:target="\_blank" rel="noopener noreferrer"}       |
|        [`gems/kaal-rails/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-rails){:target="\_blank" rel="noopener noreferrer"}        |           [![Gem Version](https://img.shields.io/gem/v/kaal-rails?style=flat-square&logo=rubygems&label=kaal-rails)](https://rubygems.org/gems/kaal-rails){:target="\_blank" rel="noopener noreferrer"}            |        [![RubyDoc](https://img.shields.io/badge/rubydoc-kaal--rails-blue.svg)](https://www.rubydoc.info/gems/kaal-rails){:target="\_blank" rel="noopener noreferrer"}        |
|         [`gems/kaal-roda/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-roda){:target="\_blank" rel="noopener noreferrer"}         |             [![Gem Version](https://img.shields.io/gem/v/kaal-roda?style=flat-square&logo=rubygems&label=kaal-roda)](https://rubygems.org/gems/kaal-roda){:target="\_blank" rel="noopener noreferrer"}             |         [![RubyDoc](https://img.shields.io/badge/rubydoc-kaal--roda-blue.svg)](https://www.rubydoc.info/gems/kaal-roda){:target="\_blank" rel="noopener noreferrer"}         |
|      [`gems/kaal-sinatra/`](https://github.com/Code-Vedas/kaal/tree/main/gems/kaal-sinatra){:target="\_blank" rel="noopener noreferrer"}      |        [![Gem Version](https://img.shields.io/gem/v/kaal-sinatra?style=flat-square&logo=rubygems&label=kaal-sinatra)](https://rubygems.org/gems/kaal-sinatra){:target="\_blank" rel="noopener noreferrer"}         |      [![RubyDoc](https://img.shields.io/badge/rubydoc-kaal--sinatra-blue.svg)](https://www.rubydoc.info/gems/kaal-sinatra){:target="\_blank" rel="noopener noreferrer"}      |
