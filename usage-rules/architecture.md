# Nebulex Architecture

This guide explains why Nebulex exists, who uses it, how it is structured
internally, and the non-negotiable design principles that govern every
contribution. Read it at session start to establish project context, and
refer back to it when making structural changes.

---

## Why Nebulex Exists

Elixir applications need caching. But caching backends — Redis, local ETS,
Memcached, Cachex, distributed cluster caches — each have their own APIs,
semantics, and failure modes. Without an abstraction layer, teams either
lock themselves into a single backend or scatter adapter-specific code
throughout their application.

Nebulex solves this the same way [Ecto][ecto] solved it for databases:
a **unified caching abstraction** that lets you swap backends, compose
topologies, and add declarative caching to any function — without changing
application code.

> "Give users explicit control over failure handling, while keeping the
> API ergonomic." — core design principle established in v3

Nebulex has been in production since 2017. It serves read-heavy workloads,
configuration caching, session management, and high-concurrency scenarios
across local, distributed, and hybrid cache setups.

[ecto]: https://github.com/elixir-ecto/ecto

---

## Who Uses It

Nebulex is used by Elixir teams who need:

- **Backend flexibility** — switch from a local ETS cache in development to
  Redis or a distributed cluster in production without changing application
  code.
- **Declarative caching** — annotate functions with `@decorate cacheable(...)`,
  `@decorate cache_put(...)`, or `@decorate cache_evict(...)` and let Nebulex
  handle the cache lifecycle automatically.
- **Composed topologies** — layer a local cache in front of a Redis cache, or
  run a coherent local cache with distributed invalidation, without writing
  topology-specific code.
- **Graceful degradation** — handle cache infrastructure failures (timeouts,
  connection drops, cluster failovers) differently from database failures,
  because a cache outage often permits fallback to the source of record.

---

## High-Level Architecture

Nebulex is organized into three distinct layers:

```ascii
+-------------------------------------------------------------+
|                     Application Layer                       |
|         (your modules using Nebulex.Cache API or            |
|          declarative caching decorators)                    |
+-------------------------------------------------------------+
                           |
+------------------------------------------------------------+
|                      Core Layer                            |
|                                                            |
|  +------------------+   +-------------------------------+  |
|  |  Nebulex.Cache   |<--|     Nebulex.Caching           |  |
|  |  (public API)    |   |  (declarative decorators)     |  |
|  +------------------+   +-------------------------------+  |
|            |                                               |
|            v                                               |
|  +-------------------------------------------------------+ |
|  |           Nebulex.Adapter behaviours                  | |
|  |  (KV, CompositeKV, Queryable, Transaction,            | |
|  |   Observable, Info)                                   | |
|  +-------------------------------------------------------+ |
+------------------------------------------------------------+
                           |
+------------------------------------------------------------+
|                     Adapter Layer                          |
|  (separate packages: nebulex_local, nebulex_distributed,   |
|   nebulex_redis_adapter, nebulex_adapters_cachex, etc.)    |
+------------------------------------------------------------+
```

### Core Layer — `lib/nebulex/`

The core package provides the abstraction. It contains no production cache
implementation; all storage logic lives in adapters.

| Module | Responsibility |
|---|---|
| `Nebulex.Cache` | Public API macro — `use Nebulex.Cache` generates the full cache API for a module |
| `Nebulex.Cache.KV` | Key-value operations: `fetch`, `get`, `put`, `delete`, `take`, etc. |
| `Nebulex.Cache.CompositeKV` | Composite KV operations (`get_and_update`, `update`, `fetch_or_store`, `get_or_store`) when the adapter implements `Nebulex.Adapter.CompositeKV` |
| `Nebulex.Cache.Queryable` | Query-based operations: `get_all`, `count_all`, `delete_all` |
| `Nebulex.Cache.Transaction` | Optimistic locking and transactional operations |
| `Nebulex.Cache.Observable` | Event streaming for cache entry changes |
| `Nebulex.Cache.Info` | Stats and monitoring (`info/2`) |
| `Nebulex.Cache.Options` | NimbleOptions-based validation for all cache options |
| `Nebulex.Cache.Supervisor` | OTP supervision tree for cache processes |
| `Nebulex.Cache.Registry` | Registry for dynamic caches |
| `Nebulex.Adapter` | Adapter behaviour definition and shared macros |
| `Nebulex.Adapter.KV` | Callback spec for KV operations |
| `Nebulex.Adapter.CompositeKV` | Callback spec for composite KV operations (optional) and their default implementation |
| `Nebulex.Adapter.Queryable` | Callback spec for query operations |
| `Nebulex.Adapter.Transaction` | Callback spec for transaction operations |
| `Nebulex.Adapter.Observable` | Callback spec for event streaming |
| `Nebulex.Adapter.Info` | Callback spec for stats/info |
| `Nebulex.Caching` | Entry point for declarative caching (`use Nebulex.Caching`) |
| `Nebulex.Caching.Decorators` | `cacheable`, `cache_put`, `cache_evict` decorator implementations |
| `Nebulex.Caching.Decorators.Runtime` | Runtime evaluation of cache operations, key generation, match logic |
| `Nebulex.Caching.Decorators.Context` | Per-invocation decorator context (function name, args, decorator type) |
| `Nebulex.Telemetry` | Telemetry span events emitted by cache operations |
| `Nebulex.Event` | Cache entry event types for the Observable API |

### Adapter Layer — separate packages

Each adapter is its own Hex package. The core package ships only with
`Nebulex.Adapters.Nil` (a no-op adapter used for benchmarking the abstraction
layer itself) and `Nebulex.Adapters.Common.Info.Stats` (shared stats helpers).

For the canonical list of official adapters (package names, modules,
and Hex/GitHub links), see `guides/introduction/nbx-adapters.md`. That
guide is the single source of truth — do not maintain a parallel list here.

### Declarative Caching — `Nebulex.Caching`

Declarative caching is built on the [`decorator`][decorator-lib] library.
`use Nebulex.Caching` registers three function decorators:

- `cacheable` — read-through: skip execution on cache hit, populate on miss
- `cache_put` — write-through: always execute, always update the cache
- `cache_evict` — invalidation: execute and remove entries from the cache

The decorator macro captures key expressions and option lambdas as AST at
compile time and inlines them into generated wrapper functions. All runtime
resolution (key generation, cache selection, match evaluation) happens in
Nebulex.Caching.Decorators.Runtime.

[decorator-lib]: https://github.com/arjan/decorator

---

## Key Design Decisions

### ok/error tuples everywhere

All cache operations return `{:ok, value}` or `{:error, reason}` by default.
Bang variants (`fetch!/2`, `put!/3`, etc.) are available for fail-fast
semantics. This was a deliberate v3 decision: cache infrastructure failures
should be handled explicitly at each call site, not swallowed silently.

### Adapters are decoupled — always

The core package has no runtime dependency on any adapter package. Adapters
depend on core, never the reverse. The adapter callback specs (`Nebulex.Adapter.*`)
define the contract; the core enforces it at compile time via behaviours.

This decoupling means adapters evolve independently. A breaking change in an
adapter does not require a core release. New adapters can be published by
anyone without touching the core repository.

### Optional dependencies

No dependency in `mix.exs` is required. `:telemetry`, `:decorator`, and all
adapters are optional. This keeps the core footprint minimal for users who
only need a subset of features. If a dependency is absent, the feature it
enables is simply unavailable (no runtime error, no silent failure).

### NimbleOptions for all option validation

Every public option set — cache options, decorator options, adapter-specific
options — is validated through [NimbleOptions][nimble_options] schemas. This
produces consistent, actionable error messages at compile time or startup,
rather than cryptic runtime failures.

[nimble_options]: https://hexdocs.pm/nimble_options

### Telemetry as the observability contract

The core emits consistent `[:nebulex, :cache, <operation>, :start/stop/exception]`
Telemetry span events for every cache operation, regardless of which adapter
is in use. Adapters may emit additional events but must not suppress or
redefine core events. This guarantees that monitoring dashboards and
telemetry handlers work across backend switches.

### Nil is a valid cache value

Since v3, `nil` can be cached. The sentinel-value restriction from v2 (where
`nil` meant "cache miss") is gone. Match functions control whether a result
is cached, giving developers explicit control over nil caching.

---

## Non-Negotiables

These rules are not open for debate. Any contribution that violates them
will not be merged, regardless of other merits.

### 1. Adapters must remain decoupled from core

The core package must not import, alias, or depend on any adapter module at
runtime. Shared utilities belong in `Nebulex.Adapters.Common.*` within the
core, not in adapter packages. If you find yourself adding an adapter-specific
module to the core, stop and reconsider.

### 2. No breaking public API changes without a major version

`Nebulex.Cache`, `Nebulex.Caching`, and all `Nebulex.Adapter.*` callback specs
are public API. Removing or renaming public functions, changing callback
signatures, or altering option semantics requires a major version bump
(`v3.x` → `v4.0`). Deprecation warnings must precede removals by at least
one minor release.

### 3. Every public function must have a `@doc` and typespec

Module documentation (`@moduledoc`) is required for every module. Public
functions require `@doc` and `@spec`. This is enforced by `mix doctor` in CI
and is not optional. Undocumented public API will not be merged.

### 4. New behaviour must have tests

Any new feature, option, or code path must be accompanied by tests. For
adapter-facing changes, tests belong in `test/shared/` using the `deftests`
macro so the shared test suite covers all adapters consistently. For
core-only changes, tests belong in `test/nebulex/`. A PR without tests for
new behaviour will not be merged.

### 5. `mix precommit` must pass

All changes must pass the full CI suite locally before opening a PR:

```bash
mix precommit
```

This runs tests, coverage, Credo (strict), Dialyzer, Sobelow, `mix deps.audit`,
and `mix doctor`.
Green CI on the PR is a requirement, not a courtesy check.

### 6. Keep this document up to date

After any structural change — new module, new adapter callback, new public
option, new dependency, or changes to the layer boundaries — review this
document and update it if needed. Architecture docs rot when nobody owns them.
This is not a checkbox on every PR, but a conscious check: "did my change
affect the architecture described here?"

### 7. `mix docs` must produce no warnings

Documentation must build cleanly:

```bash
mix docs
```

No warnings are acceptable. Common causes: referencing hidden modules with
backtick syntax, broken links, or missing `@doc`/`@moduledoc`. Fix the root
cause — do not suppress warnings.

---

## Source of Truth Hierarchy

When in doubt about intent, consult these sources in order:

1. `usage-rules/workflow.md` — contribution workflow and rule precedence
2. This document — architectural decisions and non-negotiables
3. `usage-rules/nebulex.md` — domain-specific patterns and pitfalls
4. Module `@moduledoc` and function `@doc` — local intent for each API
5. `CHANGELOG.md` — history of decisions and the reasoning behind them
6. The blog post ["Nebulex v3: A New Chapter for Caching in Elixir"][v3-post]
   for the philosophy behind the v3 redesign

[v3-post]: https://medium.com/erlang-battleground/nebulex-v3-a-new-chapter-for-caching-in-elixir-03cd366692c3
