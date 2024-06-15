# Nebulex 🌌
> In-memory and distributed caching toolkit for Elixir.

![CI](https://github.com/cabol/nebulex/workflows/CI/badge.svg)
[![Coverage Status](https://img.shields.io/coveralls/cabol/nebulex.svg)](https://coveralls.io/github/cabol/nebulex)
[![Hex Version](https://img.shields.io/hexpm/v/nebulex.svg)](https://hex.pm/packages/nebulex)
[![Docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/nebulex)
[![License](https://img.shields.io/hexpm/l/nebulex.svg)](LICENSE)

Nebulex provides support for transparently adding caching into an existing
Elixir application. Like [Ecto][ecto], the caching abstraction allows consistent
use of various caching solutions with minimal impact on the code.

Nebulex cache abstraction shields developers from directly dealing with the
underlying caching implementations, such as [Redis][redis],
[Memcached][memcached], or even other Elixir cache implementations like
[Cachex][cachex]. Additionally, it provides out-of-box features such as
[declarative decorator-based caching][nbx_caching],
[cache usage patterns][cache_patterns], and
[distributed cache topologies][cache_topologies], among others.

See the [getting started guide](http://hexdocs.pm/nebulex/getting-started.html)
and the [online documentation](http://hexdocs.pm/nebulex/Nebulex.html)
for more information.

[ecto]: https://github.com/elixir-ecto/ecto
[cachex]: https://github.com/whitfin/cachex
[redis]: https://redis.io/
[memcached]: https://memcached.org/
[nbx_caching]: http://hexdocs.pm/nebulex/Nebulex.Caching.Decorators.html
[cache_patterns]: http://hexdocs.pm/nebulex/cache-usage-patterns.html
[cache_topologies]: https://docs.oracle.com/middleware/1221/coherence/develop-applications/cache_intro.htm

## Usage

You need to add both Nebulex and the cache adapter as a dependency to your
`mix.exs` file. The supported caches and their adapters are:

Cache | Nebulex Adapter | Dependency
:-----| :---------------| :---------
Nil (special adapter to disable caching) | [Nebulex.Adapters.Nil][nil] | Built-In
Generational Local Cache | Nebulex.Adapters.Local | [nebulex_adapters_local][la]
Partitioned | Nebulex.Adapters.Partitioned | [nebulex_adapters_partitioned][pa]
Replicated | Nebulex.Adapters.Replicated | [nebulex_adapters_replicated][ra]
Multilevel | Nebulex.Adapters.Multilevel | [nebulex_adapters_multilevel][ma]
Redis | NebulexRedisAdapter | [nebulex_redis_adapter][nbx_redis]
Cachex | Nebulex.Adapters.Cachex | [nebulex_adapters_cachex][nbx_cachex]
Distributed with Horde | Nebulex.Adapters.Horde | [nebulex_adapters_horde][nbx_horde]
Multilevel with cluster broadcasting | NebulexLocalMultilevelAdapter | [nebulex_local_multilevel_adapter][nbx_local_multilevel]

[nil]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Nil.html
[la]: https://github.com/elixir-nebulex/nebulex_adapters_local
[pa]: https://github.com/elixir-nebulex/nebulex_adapters_partitioned
[ra]: https://github.com/elixir-nebulex/nebulex_adapters_replicated
[ma]: https://github.com/elixir-nebulex/nebulex_adapters_multilevel
[nbx_redis]: https://github.com/cabol/nebulex_redis_adapter
[nbx_cachex]: https://github.com/cabol/nebulex_adapters_cachex
[nbx_horde]: https://github.com/eliasdarruda/nebulex_adapters_horde
[nbx_local_multilevel]: https://github.com/slab/nebulex_local_multilevel_adapter

For example, if you want to use the Nebulex Generational Local Cache
(`Nebulex.Adapters.Local` adapter), add to your `mix.exs` file:

```elixir
def deps do
  [
    {:nebulex, "~> 3.0"},
    {:nebulex_adapters_local, "~> 3.0"},
    {:decorator, "~> 1.4"},  #=> For Caching decorators (recommended adding it)
    {:telemetry, "~> 1.2"}   #=> For Telemetry events (recommended adding it)
  ]
end
```

To give more flexibility and load only needed dependencies, Nebulex makes all
dependencies optional. For example:

  * For enabling [declarative decorator-based caching][nbx_caching], you
    have to add `:decorator` to the dependency list (recommended adding it).

  * For enabling Telemetry events dispatched by Nebulex, you have to add
    `:telemetry` to the dependency list (recommended adding it).
    See [telemetry guide][telemetry].

[telemetry]: http://hexdocs.pm/nebulex/telemetry.html

Then run `mix deps.get` in your shell to fetch the dependencies. If you want to
use another cache adapter, just choose the proper dependency from the table
above.

Finally, in the cache definition, you will need to specify the `adapter:`
respective to the chosen dependency. For the local cache would be:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

## Quickstart example using caching decorators

Assuming you are using `Ecto` and you want to use declarative caching:

```elixir
# In the config/config.exs file
config :my_app, MyApp.Cache,
  # Create new generation every 12 hours
  gc_interval: :timer.hours(12),
  # Max 1M entries
  max_size: 1_000_000,
  # Max 2GB of memory
  allocated_memory: 2_000_000_000,
  # Run size and memory checks every 10 seconds
  gc_memory_check_interval: :timer.seconds(10)

# Defining the cache
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end

# Ecto schema
defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :username, :string
    field :password, :string
    field :role, :string
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :role])
    |> validate_required([:username, :password, :role])
  end
end

# The Accounts context
defmodule MyApp.Accounts do
  use Nebulex.Caching, cache: MyApp.Cache

  alias MyApp.Accounts.User
  alias MyApp.Repo

  @ttl :timer.hours(1)

  @decorate cacheable(key: {User, id}, opts: [ttl: @ttl])
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @decorate cacheable(key: {User, username}, references: & &1.id)
  def get_user_by_username(username) do
    Repo.get_by(User, [username: username])
  end

  @decorate cache_put(
              key: {User, user.id},
              match: &__MODULE__.match_update/1,
              opts: [ttl: @ttl]
            )
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @decorate cache_evict(key: {User, user.id})
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def match_update({:ok, value}), do: {true, value}
  def match_update({:error, _}), do: false
end
```

See more [Nebulex examples](https://github.com/cabol/nebulex_examples).

## Important links

* [Getting Started](http://hexdocs.pm/nebulex/getting-started.html)
* [Documentation](http://hexdocs.pm/nebulex/Nebulex.html)
* [Migrating to v3.x](http://hexdocs.pm/nebulex/migrating-to-v3.html)
* [Cache Usage Patterns](http://hexdocs.pm/nebulex/cache-usage-patterns.html)
* [Instrumenting the Cache with Telemetry](http://hexdocs.pm/nebulex/telemetry.html)
* [Examples](https://github.com/cabol/nebulex_examples)

## Testing

To run only the tests:

```
$ mix test
```

Additionally, to run all Nebulex checks run:

```
$ mix check
```

The `mix check` will run the tests, coverage, credo, dialyzer, etc. This is the
recommended way to test Nebulex.

## Benchmarks

Nebulex provides a set of basic benchmark tests using the library
[benchee](https://github.com/PragTob/benchee), and they are located within
the directory [benchmarks](./benchmarks).

To run a benchmark test you have to run:

```
$ mix run benchmarks/benchmark.exs
```

> The benchmark uses the `Nebulex.Adapters.Nil` adapter; it is more focused on
> measuring the Nebulex abstraction layer performance rather than a specific
> adapter.

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
