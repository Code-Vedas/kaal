# CHANGELOG

## [0.3.0](https://github.com/code-vedas/kaal/tree/v0.3.0) (2026-03-24)

[Full Changelog](https://github.com/code-vedas/kaal/compare/v0.2.1...v0.3.0)

### 🚀 Features

- feat: add contention integration tests for various backends @niteshpurohit (#84)
- feat: add Kaal integration for Hanami applications @niteshpurohit (#83)
- feat: add Kaal integration for Roda applications @niteshpurohit (#82)
- feat: add Kaal Sinatra integration and tests @niteshpurohit (#78)
- feat: add time zone support for cron scheduling @niteshpurohit (#70)

### 📝 Documentation

- docs: update security and documentation for Kaal @niteshpurohit (#86)

### 🧰 Maintenance

- build(deps): bump rubygems/configure-rubygems-credentials from a991f145d5e4a60c4b0a3ddb204f557dc1a4f985 to c631c084989f8f5953cd1cdbfb04e4cf3dba10aa @[dependabot[bot]](https://github.com/apps/dependabot) (#85)
- build(deps): bump rubygems/configure-rubygems-credentials from 84d1838d405cabde880feada9a63c0b49f659ebd to a991f145d5e4a60c4b0a3ddb204f557dc1a4f985 @[dependabot[bot]](https://github.com/apps/dependabot) (#79)
- build(deps-dev): bump activesupport from 8.1.2 to 8.1.2.1 in /docs in the bundler group across 1 directory @[dependabot[bot]](https://github.com/apps/dependabot) (#80)
- build(deps): bump activesupport from 8.1.2 to 8.1.2.1 in /danger in the bundler group across 1 directory @[dependabot[bot]](https://github.com/apps/dependabot) (#81)
- build(deps): bump release-drafter/release-drafter from 6 to 7 @[dependabot[bot]](https://github.com/apps/dependabot) (#68)
- refactor: split kaal into core, datastore adapters, and rails plugin @niteshpurohit (#75)
- refactor: reorganize internal domains and align docs with runtime behavior @niteshpurohit (#74)

### ⚙️ CI

- ci: improve bundle installation process @niteshpurohit (#87)

## [0.2.1](https://github.com/code-vedas/kaal/tree/v0.2.1) (2026-03-12)

[Full Changelog](https://github.com/code-vedas/kaal/compare/v0.2.0...v0.2.1)

### 🧰 Maintenance

- refactor: streamline gem information and copyright information @niteshpurohit (#66)

## [0.2.0](https://github.com/code-vedas/kaal/tree/v0.2.0) (2026-03-12)

[Full Changelog](https://github.com/code-vedas/kaal/compare/v0.1.0...v0.2.0)

### Breaking Changes

- refactor: hard reset project identity to kaal @niteshpurohit (#62)
  - RailsCron => Kaal
  - rails_cron => kaal
  - RAILS_CRON => KAAL
  - Update namespaces, module names, and references accordingly

### 🚀 Features

- feat: add scheduler configuration support @niteshpurohit (#54)
- feat: implement backend adapters for cron job dispatching @niteshpurohit (#52)
- feat: enhance scheduler documentation and signal handling @niteshpurohit (#47)
- feat: add Rake tasks for RailsCron management @niteshpurohit (#46)
- feat: integrate localization support for cron phrases @niteshpurohit (#45)
- feat: add cron utilities for validation and simplification @niteshpurohit (#44)
- feat: add idempotency key generation and logging @niteshpurohit (#42)
- feat: implement dispatch registry and recovery mechanisms @niteshpurohit (#38)
- feat: add MySQL support for distributed locking @niteshpurohit (#37)
- feat: add InMemory, PostgreSQL and Redis lock adapters @niteshpurohit (#35)
- feat: implement coordinator and locking mechanism @niteshpurohit (#33)
- feat: add configuration and registry for RailsCron @niteshpurohit (#32)

### 🧰 Maintenance

- build(deps): bump action_text-trix from 2.1.16 to 2.1.17 in the bundler group across 1 directory @[dependabot[bot]](https://github.com/apps/dependabot) (#57)
- build(deps-dev): bump ruby-lsp-rspec from 0.1.28 to 0.1.29 @[dependabot[bot]](https://github.com/apps/dependabot) (#55)
- build(deps-dev): bump sqlite3 from 2.9.0 to 2.9.1 @[dependabot[bot]](https://github.com/apps/dependabot) (#48)
- build(deps-dev): bump ruby-lsp from 0.26.6 to 0.26.7 @[dependabot[bot]](https://github.com/apps/dependabot) (#43)
- build(deps-dev): bump nokogiri from 1.19.0 to 1.19.1 in /docs in the bundler group across 1 directory @[dependabot[bot]](https://github.com/apps/dependabot) (#41)
- build(deps): bump rack from 3.2.4 to 3.2.5 in the bundler group across 1 directory @[dependabot[bot]](https://github.com/apps/dependabot) (#39)
- build(deps-dev): bump rspec-rails from 8.0.2 to 8.0.3 @[dependabot[bot]](https://github.com/apps/dependabot) (#40)
- chore: dependencies update and rails 8.1 testing @niteshpurohit (#29)
- build(deps-dev): bump sqlite3 from 2.7.4 to 2.8.0 @[dependabot[bot]](https://github.com/apps/dependabot) (#18)
- chore: Enable CSRF protection in dummy app @niteshpurohit (#17)

### 🧪 Tests

- test: enhance integration tests and add scheduler helpers @niteshpurohit (#56)

### ⚙️ CI

- ci: update actions/checkout to v6 @niteshpurohit (#30)

## [0.1.0](https://github.com/code-vedas/kaal/tree/v0.1.0) (2025-11-04)

[Full Changelog](https://github.com/code-vedas/kaal/compare/197ad36e7e482b0541b8162d779b55cbd58a4868...v0.1.0)

## 📦 Build

- build: kaal gem skeleton @niteshpurohit (#15)
