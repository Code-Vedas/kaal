---
title: Become a contributor
layout: page
nav_order: 10
permalink: /contribute
---

# Become a contributor

## Basic flow

1. Fork the repository.
2. Clone your fork and create a branch.
3. Make your changes.
4. Run the local checks:

   ```bash
   bundle install
   cd kaal
   bundle exec rspec
   bin/rubocop
   bin/reek
   ```

5. Push and open a pull request.

## Code structure

- `Kaal::Core` for scheduling and coordination logic
- `Kaal::Config` for configuration and validation
- `Kaal::Runtime` for runtime lifecycle helpers
- `Kaal::SchedulerFile` for scheduler file loading
- `Kaal::Backend` for adapters and backend-facing helpers
- `Kaal::Definitions` for definition persistence and registration
- `Kaal::Utils` for pure helpers

You do not need framework-specific experience to contribute. Plain Ruby, SQL, Redis, documentation, and test improvements are all useful.
