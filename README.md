# Nebulex 🌌
> ### In-Process and Distributed Cache Toolkit for Elixir.
> Easily craft and deploy distributed cache topologies and cache usage patterns.

![CI](https://github.com/cabol/nebulex/workflows/CI/badge.svg)
[![Coverage Status](https://coveralls.io/repos/github/cabol/nebulex/badge.svg?branch=master)](https://coveralls.io/github/cabol/nebulex?branch=master)
[![Inline docs](http://inch-ci.org/github/cabol/nebulex.svg)](http://inch-ci.org/github/cabol/nebulex)
[![Hex Version](https://img.shields.io/hexpm/v/nebulex.svg)](https://hex.pm/packages/nebulex)
[![Docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/nebulex)

**Nebulex** provides support for transparently adding caching into an existing
Elixir application. Similar to [Ecto][ecto], the caching abstraction allows
consistent use of various caching solutions with minimal impact on the code.
Furthermore, it enables the implementation of different
[cache usage patterns][cache_patterns],
[distributed cache topologies][cache_topologies],
and more.

[ecto]: https://github.com/elixir-ecto/ecto
[cache_patterns]: https://github.com/ehcache/ehcache3/blob/master/docs/src/docs/asciidoc/user/caching-patterns.adoc
[cache_topologies]: https://docs.oracle.com/middleware/1221/coherence/develop-applications/cache_intro.htm

Supposing we are using `Ecto` and we want to apply caching declaratively on
some functions:

```elixir
# In the config/config.exs file
config :my_app, MyApp.PartitionedCache.Primary,
  gc_interval: Nebulex.Time.expiry_time(1, :hour),
  partitions: 2

# Defining a Cache with a partitioned topology
defmodule MyApp.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Partitioned,
    primary: MyApp.PartitionedCache.Primary

  defmodule Primary do
    use Nebulex.Cache,
      otp_app: :my_app,
      adapter: Nebulex.Adapters.Local,
      backend: :shards
  end
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

  @ttl Nebulex.Time.expiry_time(1, :hour)

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
              keys: [{User, usr.id}, {User, usr.username}],
              match: &match_update/1
            )
  def update_user(%User{} = usr, attrs) do
    usr
    |> User.changeset(attrs)
    |> Repo.update()
  end

  defp match_update({:ok, usr}), do: {true, usr}
  defp match_update({:error, _}), do: false

  @decorate cache_evict(cache: Cache, keys: [{User, usr.id}, {User, usr.username}])
  def delete_user(%User{} = usr) do
    Repo.delete(usr)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```

Nebulex is commonly used to interact with different cache implementations and/or
stores (such as Redis, Memcached, or other implementations of cache in Elixir),
being completely agnostic from them, avoiding the vendor lock-in.

See the [getting started guide](http://hexdocs.pm/nebulex/getting-started.html)
and the [online documentation](http://hexdocs.pm/nebulex/Nebulex.html)
for more information.

## Usage

You need to add `nebulex` as a dependency to your `mix.exs` file. However, in
the case you want to use an external (a non built-in adapter) cache adapter,
you also have to add the proper dependency to your `mix.exs` file.

The supported caches and their adapters are:

Cache | Nebulex Adapter | Dependency
:-----| :---------------| :---------
Generational Local Cache (ETS + Shards) | [Nebulex.Adapters.Local][la] | Built-In
Partitioned (layer on top of a local cache) | [Nebulex.Adapters.Partitioned][pa] | Built-In
Replicated (layer on top of a local cache) | [Nebulex.Adapters.Replicated][ra] | Built-In
Multilevel (layer on top of existing caches) | [Nebulex.Adapters.Multilevel][ma] | Built-In
Redis | NebulexRedisAdapter | [nebulex_redis_adapter][nebulex_redis_adapter]
Memcached | NebulexMemcachedAdapter | [nebulex_memcached_adapter][nebulex_memcached_adapter]
FoundationDB | NebulexFdbAdapter | [nebulex_fdb_adapter][nebulex_fdb_adapter]

[la]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Local.html
[pa]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Partitioned.html
[ra]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Replicated.html
[ma]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Multilevel.html
[nebulex_redis_adapter]: https://github.com/cabol/nebulex_redis_adapter
[nebulex_memcached_adapter]: https://github.com/vasuadari/nebulex_memcached_adapter
[nebulex_fdb_adapter]: https://github.com/fire/nebulex_fdb_adapter

For example, if you want to use a built-in cache, add to your `mix.exs` file:

```elixir
def deps do
  [
    {:nebulex, "~> 2.0"},
    {:decorator, "~> 1.3"}
  ]
end
```

> The `:decorator` dependency is for enabling
  [declarative annotation-based caching via decorators][nbx_caching].

[nbx_caching]: http://hexdocs.pm/nebulex/Nebulex.Caching.html

Then run `mix deps.get` in your shell to fetch the dependencies. If you want to
use another cache adapter, just choose the proper dependency from the table
above.

Finally, in the cache definition, you will need to specify the `adapter:`
respective to the chosen dependency. For the local built-in cache it is:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local,
    backend: :shards
  ...
```

## Important links

 * [Getting Started](http://hexdocs.pm/nebulex/getting-started.html)
 * [Documentation](http://hexdocs.pm/nebulex/Nebulex.html)
 * [Cache Usage Patterns via Nebulex.Caching](http://hexdocs.pm/nebulex/cache-usage-patterns.html)
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

Some basic benchmarks were added using [benchee](https://github.com/PragTob/benchee);
to learn more, check out the [benchmarks](./benchmarks) directory.

To run the benchmarks:

```
$ MIX_ENV=test mix run benchmarks/benchmark.exs
```

If you are interested to run more sophisticated load tests, perhaps you should
checkout the [Nebulex Load Tests](https://github.com/cabol/nebulex_examples/tree/master/nebulex_bench)
example, it allows you to run your own performance/load tests against Nebulex,
and it also comes with load tests results.

## Contributing

Contributions to Nebulex are very welcome and appreciated!

Use the [issue tracker](https://github.com/cabol/nebulex/issues) for bug reports
or feature requests. Open a [pull request](https://github.com/cabol/nebulex/pulls)
when you are ready to contribute.

When submitting a pull request you should not update the [CHANGELOG.md](CHANGELOG.md),
and also make sure you test your changes thoroughly, include unit tests
alongside new or changed code.

Before to submit a PR it is highly recommended to run:

 * `mix test` to run tests
 * `mix coveralls.html && open cover/excoveralls.html` to run tests and check
   out code coverage (expected 100%).
 * `mix format && mix credo --strict` to format your code properly and find code
   style issues
 * `mix dialyzer` to run dialyzer for type checking; might take a while on the
   first invocation

## Copyright and License

Copyright (c) 2017, Carlos Bolaños.

Nebulex source code is licensed under the [MIT License](LICENSE).
