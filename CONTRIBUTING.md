# Contributing to Nebulex

Thanks for your interest in contributing.

This guide defines the expected contribution workflow for the `nebulex` core
repository.

## Scope

This repository contains Nebulex core. Adapter projects (for example
`nebulex_local`, `nebulex_distributed`) are maintained in sibling repositories
and have their own contribution rules.

## Before You Start

1. Read `README.md`.
2. Read the latest section of `CHANGELOG.md`.
3. Read `usage-rules/workflow.md` (source of coding/review conventions used in
   this repo).

## Issues

Use the issue tracker for bug reports and feature discussions:

- https://github.com/elixir-nebulex/nebulex/issues

When opening a bug report, include:

- Elixir and OTP versions
- Nebulex version/branch
- Minimal reproduction steps
- Expected vs actual behavior

## Feature Requests

Feature proposals are welcome.

For non-trivial features, open an issue first before implementing code so
scope and design can be aligned early.

When proposing a feature, include:

- Problem statement.
- Real-world use case.
- Proposed API/behavior.
- Alternatives considered.

## Pull Requests

Open pull requests at:

- https://github.com/elixir-nebulex/nebulex/pulls

### PR Expectations

1. Keep changes focused and avoid unrelated commits.
2. Add or update tests with code changes.
3. Update documentation when behavior changes.
4. Do not update CHANGELOG.md directly; include release-note context in the PR
   description for maintainers.
5. Reference related issues (for example, `Closes #123`).

### Validation

Run targeted checks during development and run the full CI command before
requesting review:

```bash
# quick targeted check
mix test path/to/changed_test.exs

# full validation
mix precommit
```

## Commit Message Convention

Commit messages must follow
[Conventional Commits](https://www.conventionalcommits.org/):

```text
type(scope): short summary
```

Examples:

- `feat(cache): add runtime option validation for ttl`
- `fix(decorators): handle nested context pop safely`
- `docs(workflow): add contribution and review checklist`

## Documentation Conventions

For `@doc`, `@moduledoc`, and `@typedoc`, keep the first paragraph short and
summary-oriented. Add examples when possible, ideally doctest-friendly.

## License

By submitting a contribution, you agree that your work is licensed under the
project's MIT license.
