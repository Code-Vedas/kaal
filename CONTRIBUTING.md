# Contributing to Kaal

Thank you for contributing to Kaal. This repository is a Ruby monorepo with multiple gems, a docs site, and shared development scripts. Read this guide before opening a change.

You can contribute with issues, bug reports, feature requests, documentation updates, tests, or pull requests.

## Repository layout

The main packages in this repository are:

| Package             | Path                     | Purpose                                                       |
| ------------------- | ------------------------ | ------------------------------------------------------------- |
| `kaal`              | `core/kaal`              | Core scheduler engine, CLI, memory backend, and Redis backend |
| `kaal-sequel`       | `core/kaal-sequel`       | Sequel-backed SQL adapter                                     |
| `kaal-activerecord` | `core/kaal-activerecord` | Active Record-backed SQL adapter                              |
| `kaal-hanami`       | `gems/kaal-hanami`       | Hanami integration                                            |
| `kaal-rails`        | `gems/kaal-rails`        | Rails integration                                             |
| `kaal-roda`         | `gems/kaal-roda`         | Roda integration                                              |
| `kaal-sinatra`      | `gems/kaal-sinatra`      | Sinatra integration                                           |
| Docs site           | `docs/`                  | Jekyll documentation site                                     |

Repo-level helpers live under `scripts/`.

## How to contribute

### Issues

Before opening an issue:

1. Check existing issues to avoid duplicates.
2. Use the matching issue template if one exists.
3. Include enough detail to reproduce the problem or evaluate the feature request.

### Pull requests

Before opening a pull request:

1. Create a branch from `main`.
2. Limit the change to a coherent unit of work.
3. Update docs when behavior, commands, package selection, or operations change.
4. Run the relevant checks locally.
5. Fill out the PR template completely.

Branch names should use a clear prefix such as `feature/<name>`, `bugfix/<name>`, `hotfix/<name>`, or `docs/<name>`.

## Running checks

Use the shared repo-level scripts from the repository root:

```bash
scripts/run-rubocop-all
scripts/run-reek-all
scripts/run-rspec-unit-all
scripts/run-rspec-e2e-all
scripts/run-multi-node-cli-all
```

Run either the phase-specific scripts you need:

- `scripts/run-rubocop-all`
  Runs RuboCop for every package.
- `scripts/run-reek-all`
  Runs Reek for every package.
- `scripts/run-rspec-unit-all`
  Runs unit specs for every package.
- `scripts/run-rspec-e2e-all`
  Runs end-to-end specs for every package and backend matrix.
- `scripts/run-multi-node-cli-all`
  Runs the shared multi-node CLI check for Redis, PostgreSQL, and MySQL.

Or run the full monorepo check in one command:

```bash
scripts/run-all
```

`scripts/run-all` runs the main lint and test flow across the monorepo.

You can also work from an individual package directory:

```bash
cd core/kaal
bundle install
bin/rspec-unit
bin/rubocop
bin/reek
```

Framework and adapter packages expose similar `bin/rspec-unit`, `bin/rspec-e2e`, `bin/rubocop`, and `bin/reek` entrypoints.

Run the smallest relevant set for your change, or use `scripts/run-all` when you want the full repo-level pass.

## Documentation

Documentation contributions are welcome.

The docs site is built with Jekyll from files under `docs/`.

Run the docs site locally:

```bash
cd docs
bundle install
bundle exec jekyll serve
```

Build the docs site once:

```bash
cd docs
bundle exec jekyll build
```

When code changes affect installation, package selection, runtime behavior, CLI commands, guarantees, or troubleshooting, update the relevant docs in the same pull request.

## Security

To report a security vulnerability, follow the instructions in [SECURITY.md](SECURITY.md).

## CLA

All contributors must sign the Contributor License Agreement before contributions can be accepted.

You will be prompted when opening your first pull request. Once signed, the CLA remains valid for future contributions to this repository.

## Release process

This repository releases multiple gems from one monorepo. Treat a release as a coordinated version bump across the packages that ship together.

### Prepare the release branch

1. Pick the version from the draft release notes on the [releases page](https://github.com/Code-Vedas/kaal/releases).
2. Create a release branch from `main`.

```bash
git checkout main
git pull
git checkout -b release/<version>
```

### Update versions and release notes

1. Update the version constants / gem metadata for each gem being released.
2. Confirm cross-gem dependency pins stay aligned where one package depends on another package from this monorepo.
3. Update [CHANGELOG.md](CHANGELOG.md) with a new section for `<version>` using the finalized release notes.

At minimum, review these package surfaces during release prep:

- `core/kaal`
- `core/kaal-sequel`
- `core/kaal-activerecord`
- `gems/kaal-hanami`
- `gems/kaal-rails`
- `gems/kaal-roda`
- `gems/kaal-sinatra`

### Docs sweep

Update user-facing docs when needed:

- [README.md](README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- docs under `docs/`
- package READMEs for any changed gem surfaces

### Pre-flight checks

Run the shared scripts from the repo root:

```bash
scripts/run-rubocop-all
scripts/run-reek-all
scripts/run-rspec-unit-all
scripts/run-rspec-e2e-all
scripts/run-multi-node-cli-all
```

Fix failures before opening the release PR.

### Open the release PR

1. Commit the release changes.
2. Push `release/<version>`.
3. Open a pull request into `main`.
4. Apply the release labels your workflow expects.

Example:

```bash
git add -A
git commit -m "release: prepare v<version>"
git push -u origin release/<version>
```

### Publish

After the release PR is approved and merged:

1. Create the GitHub Release with tag `v<version>`.
2. Use the same finalized release notes reflected in [CHANGELOG.md](CHANGELOG.md).
3. Let the configured GitHub Actions workflow publish the gems.

### Post-release sanity checks

After publication, verify the expected gems and versions on RubyGems and sanity-check a fresh install path for at least the main user surfaces you changed.
