---
title: Idempotency & Best Practices
nav_order: 8
permalink: /idempotency-best-practices
---

# Idempotency & Best Practices

Kaal guarantees at-most-once dispatch per `(key, fire_time)` under the documented model for Redis, Postgres, and MySQL. Use `idempotency_key` to extend that dispatch guarantee to downstream effects such as email delivery, payments, and external API writes.

Every dispatch callback receives:

- `fire_time`
- `idempotency_key`

The idempotency key format is:

```text
{namespace}-{job_key}-{fire_time.to_i}
```

## Extending The Dispatch Guarantee

```ruby
Kaal.register(
  key: "reports:daily",
  cron: "0 9 * * *",
  enqueue: ->(fire_time:, idempotency_key:) {
    inserted = EmailSendLog.insert_unique(idempotency_key: idempotency_key, fire_time: fire_time)
    return unless inserted

    DailyReportJob.perform(fire_time: fire_time, idempotency_key: idempotency_key)
  }
)
```

## Example Dedupe Boundaries

- email send logs keyed by `idempotency_key`
- invoice or payment attempts keyed by `idempotency_key`
- outbound event tables keyed by `idempotency_key`

## Custom Deduplication Store

```ruby
Kaal.with_idempotency("reports:daily", Time.now.utc) do |key|
  puts key
end
```

Use Redis, SQL, or your queue backend if you need a custom deduplication window.

For the scheduler-side guarantee and assumptions, see [At-Most-Once Dispatch Guarantee](/dispatch-guarantee).
