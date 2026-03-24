---
title: Dispatch Log & Querying History
nav_order: 7
permalink: /dispatch-log
---

# Dispatch Log & Querying History

When `enable_log_dispatch_registry = true`, Kaal records dispatch attempts in the active dispatch registry.

This registry is part of Kaal's documented at-most-once dispatch model. See [At-Most-Once Dispatch Guarantee](/dispatch-guarantee).

```ruby
Kaal.configure do |config|
  config.enable_log_dispatch_registry = true
end
```

## Common API

```ruby
registry = Kaal.dispatch_log_registry

registry.find_dispatch("reports:daily", Time.now.utc)
registry.dispatched?("reports:daily", Time.now.utc)
```

## SQL-backed registries

For `sqlite`, `postgres`, and `mysql`, the registry also supports:

```ruby
registry.find_by_key("reports:daily")
registry.find_by_node("worker-1")
registry.find_by_status("failed")
registry.cleanup(recovery_window: 7 * 24 * 60 * 60)
```

Returned values are plain Ruby hashes, not ORM relations.
