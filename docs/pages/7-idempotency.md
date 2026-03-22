---
title: Idempotency & Best Practices
nav_order: 7
permalink: /idempotency-best-practices
---

# Idempotency & Best Practices

Every dispatch callback receives:

- `fire_time`
- `idempotency_key`

The idempotency key format is:

```text
{namespace}-{job_key}-{fire_time.to_i}
```

## Basic Deduplication

```ruby
Kaal.register(
  key: "reports:daily",
  cron: "0 9 * * *",
  enqueue: ->(fire_time:, idempotency_key:) {
    return if Kaal.dispatched?("reports:daily", fire_time)

    DailyReportJob.perform(fire_time: fire_time, idempotency_key: idempotency_key)
  }
)
```

## Custom Deduplication Store

```ruby
Kaal.with_idempotency("reports:daily", Time.now.utc) do |key|
  puts key
end
```

Use Redis, SQL, or your queue backend if you need a custom deduplication window.
