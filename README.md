# Nebulex 🌌
> In-memory and distributed caching toolkit for Elixir.

![CI](https://github.com/cabol/nebulex/workflows/CI/badge.svg)
[![Coverage Status](https://img.shields.io/coveralls/cabol/nebulex.svg)](https://coveralls.io/github/cabol/nebulex)
[![Hex Version](https://img.shields.io/hexpm/v/nebulex.svg)](https://hex.pm/packages/nebulex)
[![Docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/nebulex)
[![License](https://img.shields.io/hexpm/l/nebulex.svg)](LICENSE)

Nebulex provides support for transparently adding caching into an existing
Elixir application. Similar to [Ecto][ecto], the caching abstraction allows
consistent use of various caching solutions with minimal impact on the code.

Nebulex cache abstraction shields developers from directly dealing with the
underlying caching implementations, such as [Redis][redis]
or even other Elixir cache implementations like
[Cachex][cachex]. Additionally, it provides totally out-of-box features such as
[cache usage patterns][cache_patterns],
[declarative annotation-based caching][nbx_caching], and
[distributed cache topologies][cache_topologies], among others.

See the [getting started guide](http://hexdocs.pm/nebulex/getting-started.html)
and the [online documentation](http://hexdocs.pm/nebulex/Nebulex.html)
for more information.

[ecto]: https://github.com/elixir-ecto/ecto
[cachex]: https://github.com/whitfin/cachex
[redis]: https://redis.io/
[nbx_caching]: http://hexdocs.pm/nebulex/Nebulex.Caching.html
[cache_patterns]: http://hexdocs.pm/nebulex/cache-usage-patterns.html
[cache_topologies]: https://docs.oracle.com/middleware/1221/coherence/develop-applications/cache_intro.htm

## Usage

You need to add `nebulex` as a dependency to your `mix.exs` file. However, in
the case you want to use an external (a non built-in adapter) cache adapter,
you also have to add the proper dependency to your `mix.exs` file.

The supported caches and their adapters are:

Cache | Nebulex Adapter | Dependency
:-----| :---------------| :---------
Generational Local Cache | [Nebulex.Adapters.Local][la] | Built-In
Partitioned | [Nebulex.Adapters.Partitioned][pa] | Built-In
Replicated | [Nebulex.Adapters.Replicated][ra] | Built-In
Multilevel | [Nebulex.Adapters.Multilevel][ma] | Built-In
Nil (special adapter that disables the cache) | [Nebulex.Adapters.Nil][nil] | Built-In
Cachex | Nebulex.Adapters.Cachex | [nebulex_adapters_cachex][nbx_cachex]
Redis | NebulexRedisAdapter | [nebulex_redis_adapter][nbx_redis]
Distributed with Horde | Nebulex.Adapters.Horde | [nebulex_adapters_horde][nbx_horde]
Multilevel with cluster broadcasting | NebulexLocalMultilevelAdapter | [nebulex_local_multilevel_adapter][nbx_local_multilevel]
Ecto Postgres table | Nebulex.Adapters.Ecto | [nebulex_adapters_ecto][nbx_ecto_postgres]

[la]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Local.html
[pa]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Partitioned.html
[ra]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Replicated.html
[ma]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Multilevel.html
[nil]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Nil.html
[nbx_cachex]: https://github.com/cabol/nebulex_adapters_cachex
[nbx_redis]: https://github.com/cabol/nebulex_redis_adapter
[nbx_horde]: https://github.com/eliasdarruda/nebulex_adapters_horde
[nbx_local_multilevel]: https://github.com/slab/nebulex_local_multilevel_adapter
[nbx_ecto_postgres]: https://github.com/hissssst/nebulex_adapters_ecto


For example, if you want to use a built-in cache, add to your `mix.exs` file:

```elixir
def deps do
  [
    {:nebulex, "~> 2.6"},
    {:shards, "~> 1.1"},     #=> When using :shards as backend
    {:decorator, "~> 1.4"},  #=> When using Caching Annotations
    {:telemetry, "~> 1.0"}   #=> When using the Telemetry events (Nebulex stats)
  ]
end
```

In order to give more flexibility and fetch only needed dependencies, Nebulex
makes all dependencies optional. For example:

  * For intensive workloads, you may want to use `:shards` as the backend for
    the local adapter and having partitioned tables. In such a case, you have
    to add `:shards` to the dependency list.

  * For enabling the usage of
    [declarative annotation-based caching via decorators][nbx_caching],
    you have to add `:decorator` to the dependency list.

  * For enabling Telemetry events to be dispatched when using Nebulex,
    you have to add `:telemetry` to the dependency list.
    See [telemetry guide][telemetry].

  * If you want to use an external adapter (e.g: Cachex or Redis adapter), you
    have to add the adapter dependency too.

[telemetry]: http://hexdocs.pm/nebulex/telemetry.html

Then run `mix deps.get` in your shell to fetch the dependencies. If you want to
use another cache adapter, just choose the proper dependency from the table
above.

Finally, in the cache definition, you will need to specify the `adapter:`
respective to the chosen dependency. For the local built-in cache it is:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

## Quickstart example

Assuming you are using `Ecto` and you want to use declarative caching:

```elixir
# In the config/config.exs file
config :my_app, MyApp.PartitionedCache,
  primary: [
    gc_interval: :timer.hours(12),
    backend: :shards,
    partitions: 2
  ]

# Defining a Cache with a partitioned topology
defmodule MyApp.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Partitioned,
    primary_storage_adapter: Nebulex.Adapters.Local
end

# Some Ecto schema
defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field(:username, :string)
    field(:password, :string)
    field(:role, :string)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :role])
    |> validate_required([:username, :password, :role])
  end
end

# The Accounts context
defmodule MyApp.Accounts do
  use Nebulex.Caching

  alias MyApp.Accounts.User
  alias MyApp.PartitionedCache, as: Cache
  alias MyApp.Repo

  @ttl :timer.hours(1)

  @decorate cacheable(cache: Cache, key: {User, id}, opts: [ttl: @ttl])
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @decorate cacheable(cache: Cache, key: {User, username}, opts: [ttl: @ttl])
  def get_user_by_username(username) do
    Repo.get_by(User, [username: username])
  end

  @decorate cache_put(
              cache: Cache,
              keys: [{User, user.id}, {User, user.username}],
              match: &match_update/1,
              opts: [ttl: @ttl]
            )
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @decorate cache_evict(
              cache: Cache,
              keys: [{User, user.id}, {User, user.username}]
            )
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  defp match_update({:ok, value}), do: {true, value}
  defp match_update({:error, _}), do: false
end
```

See more [Nebulex examples](https://github.com/cabol/nebulex_examples).

## Important links

  * [Getting Started](http://hexdocs.pm/nebulex/getting-started.html)
  * [Documentation](http://hexdocs.pm/nebulex/Nebulex.html)
  * [Cache Usage Patterns](http://hexdocs.pm/nebulex/cache-usage-patterns.html)
  * [Instrumenting the Cache with Telemetry](http://hexdocs.pm/nebulex/telemetry.html)
  * [Migrating to v2.x](http://hexdocs.pm/nebulex/migrating-to-v2.html)
  * [Examples](https://github.com/cabol/nebulex_examples)

## Testing

Testing by default spawns nodes internally for distributed tests. To run tests
that do not require clustering, exclude the `clustered` tag:

```
$ mix test --exclude clustered
```

If you have issues running the clustered tests try running:

```
$ epmd -daemon
```

before running the tests.

## Benchmarks

Nebulex provides a set of basic benchmark tests using the library
[benchee](https://github.com/PragTob/benchee), and they are located within
the directory [benchmarks](./benchmarks).

To run a benchmark test you have to run:

```
$ MIX_ENV=test mix run benchmarks/{BENCH_TEST_FILE}
```

Where `BENCH_TEST_FILE` can be any of:

  * `local_with_ets_bench.exs`: benchmark for the local adapter using
    `:ets` backend.
  * `local_with_shards_bench.exs`: benchmark for the local adapter using
    `:shards` backend.
  * `partitioned_bench.exs`:  benchmark for the partitioned adapter.

For example, for running the benchmark for the local adapter using `:shards`
backend:

```
$ MIX_ENV=test mix run benchmarks/local_with_shards_bench.exs
```

Additionally, you can also run performance tests using `:basho_bench`.
See [nebulex_bench example](https://github.com/cabol/nebulex_examples/tree/master/nebulex_bench)
for more information.

## Contributing

Contributions to Nebulex are very welcome and appreciated!

Use the [issue tracker](https://github.com/cabol/nebulex/issues) for bug reports
or feature requests. Open a [pull request](https://github.com/cabol/nebulex/pulls)
when you are ready to contribute.

When submitting a pull request you should not update the [CHANGELOG.md](CHANGELOG.md),
and also make sure you test your changes thoroughly, include unit tests
alongside new or changed code.

Before to submit a PR it is highly recommended to run `mix check` and ensure
all checks run successfully.

## Copyright and License

Copyright (c) 2017, Carlos Bolaños.

Nebulex source code is licensed under the [MIT License](LICENSE).
