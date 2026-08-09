<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elixir-nebulex/nebulex/main/guides/images/nbx-logo-white.png" />
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/elixir-nebulex/nebulex/main/guides/images/nbx-logo.png" />
  <img src="https://raw.githubusercontent.com/elixir-nebulex/nebulex/main/guides/images/nbx-logo.png" alt="Nebulex logo" />
</picture>

> **In-memory and distributed caching toolkit for Elixir**

---

![CI](https://github.com/elixir-nebulex/nebulex/workflows/CI/badge.svg)
[![Codecov](https://codecov.io/gh/elixir-nebulex/nebulex/graph/badge.svg)](https://codecov.io/gh/elixir-nebulex/nebulex)
[![Hex.pm](https://img.shields.io/hexpm/v/nebulex.svg)](https://hex.pm/packages/nebulex)
[![Documentation](https://img.shields.io/badge/Documentation-ff69b4)](https://hexdocs.pm/nebulex)

## 🚀 About

Nebulex provides support for transparently adding caching to existing
Elixir applications. Like [Ecto][ecto], the caching abstraction allows
consistent use of various caching solutions with minimal impact on your
code.

Nebulex's cache abstraction shields developers from directly interacting with
underlying caching implementations, such as [Redis][redis],
[Memcached][memcached], or other Elixir cache implementations like
[Cachex][cachex]. It also provides out-of-the-box features including
[declarative decorator-based caching][nbx_caching],
[cache usage patterns][cache_patterns], and
[distributed cache topologies][cache_topologies],
among others.

[ecto]: https://github.com/elixir-ecto/ecto
[cachex]: https://github.com/whitfin/cachex
[redis]: https://redis.io/
[memcached]: https://memcached.org/
[nbx_caching]: https://hexdocs.pm/nebulex/Nebulex.Caching.Decorators.html
[info_api]: https://hexdocs.pm/nebulex/info-api.html
[cache_patterns]: https://hexdocs.pm/nebulex/cache-usage-patterns.html
[cache_topologies]: https://docs.oracle.com/en/middleware/fusion-middleware/coherence/14.1.2/develop-applications/introduction-coherence-caches.html

---

> [!NOTE]
>
> This README refers to the main branch of Nebulex, not the latest released
> version on Hex. Please refer to the [getting started guide][getting_started]
> and the [official documentation][docs] for the latest stable release.

[getting_started]: https://hexdocs.pm/nebulex/getting-started.html
[docs]: https://hexdocs.pm/nebulex/Nebulex.html

---

## 📖 Usage

To use Nebulex, add both `:nebulex` and your chosen cache adapter as
dependencies in your `mix.exs` file.

> _**For more information about available adapters, check out the
> [Nebulex adapters][nbx_adapters] guide.**_

[nbx_adapters]: https://hexdocs.pm/nebulex/nbx-adapters.html

For example, to use the Generational Local Cache
(`Nebulex.Adapters.Local` adapter), add the following to your `mix.exs`:

```elixir
def deps do
  [
    {:nebulex, "~> 3.0"},
    {:nebulex_local, "~> 3.0"}, # Generational local cache adapter
    {:decorator, "~> 1.4"},     # Required for caching decorators
    {:telemetry, "~> 1.3"}      # Required for telemetry events
  ]
end
```

To provide more flexibility and load only the needed dependencies, Nebulex makes
all dependencies optional, including the adapters. For example:

  * **For enabling [declarative decorator-based caching][nbx_caching]**:
    Add `:decorator` to the dependency list (recommended).

  * **For enabling Telemetry events**: Add `:telemetry` to the dependency list
    (recommended). See the [Info API guide][info_api] for monitoring cache stats
    and metrics.

Then run `mix deps.get` in your shell to fetch the dependencies. If you want to
use another cache adapter, just choose the appropriate dependency from the table
above.

Finally, in your cache definition, you'll need to specify the `adapter:`
corresponding to the chosen dependency. For the local cache, it would be:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

Don't forget to add `MyApp.Cache` to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Cache
  ]

  # ... rest of your supervision tree
```

You're now ready to use the cache:

```elixir
iex> MyApp.Cache.put("foo", "bar")
:ok
iex> MyApp.Cache.fetch("foo")
{:ok, "bar"}
```

For more detailed information, see the
[getting started guide][getting_started-rc1] and
[online documentation][hex-docs].

[getting_started-rc1]: https://hexdocs.pm/nebulex/getting-started.html
[hex-docs]: https://hexdocs.pm/nebulex/Nebulex.html

---

## ⚡ Quick Start Example with Caching Decorators

This example demonstrates how to use Nebulex with Ecto and declarative caching:

```elixir
# In config/config.exs
config :my_app, MyApp.Cache,
  # Create new generation every 12 hours
  gc_interval: :timer.hours(12),
  # Max 1M entries
  max_size: 1_000_000,
  # Max 2GB of memory
  allocated_memory: 2_000_000_000,
  # Run size and memory checks every 10 seconds
  gc_memory_check_interval: :timer.seconds(10)

# Cache definition
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

# Accounts context with caching
defmodule MyApp.Accounts do
  use Nebulex.Caching, cache: MyApp.Cache

  alias MyApp.Accounts.User
  alias MyApp.Repo

  # Cache entries expire after 1 hour
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

---

## 🔗 Important Links

* [Getting Started][getting_started] - Learn how to set up and use Nebulex.
* [Documentation][docs] - Complete API reference.
* [Upgrading to v3.0][upgrading_to_v3] - Migration guide for v3.0.
* [Declarative caching][declarative_caching] - Declarative Caching: Patterns
  and Best Practices.
* [Nebulex Streams][nebulex_streams] - Real-time event streaming for Nebulex
  caches via `Phoenix.PubSub`.
* [Examples][examples] - Example applications.

[examples]: https://github.com/elixir-nebulex/nebulex_examples
[upgrading_to_v3]: https://hexdocs.pm/nebulex/v3-0.html
[nebulex_streams]: https://github.com/elixir-nebulex/nebulex_streams
[declarative_caching]: https://hexdocs.pm/nebulex/declarative-caching.html

---

## 🧪 Testing

To run only the tests:

```bash
$ mix test
```

Additionally, to run all Nebulex checks:

```bash
$ mix precommit
```

The `mix precommit` command will run the tests, coverage, credo, dialyzer,
and more. This is the recommended way to test Nebulex.

---

## 📊 Benchmarks

Nebulex provides a set of basic benchmark tests using the library
[benchee](https://github.com/PragTob/benchee), located in the
[benchmarks](./benchmarks) directory.

To run a benchmark test:

```bash
$ mix bench
```

> The benchmark uses the `Nebulex.Adapters.Nil` adapter; it is more focused on
> measuring the Nebulex abstraction layer performance rather than a specific
> adapter.

---

## 🤝 Contributing

Contributions to Nebulex are very welcome and appreciated!

Use the [issue tracker](https://github.com/elixir-nebulex/nebulex/issues)
for bug reports or feature requests. Open a
[pull request](https://github.com/elixir-nebulex/nebulex/pulls)
when you're ready to contribute.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for the full contribution
workflow, PR expectations, commit message conventions, and validation steps.

---

## 📄 Copyright and License

Copyright (c) 2017, Carlos Bolaños.

Nebulex source code is licensed under the [MIT License](LICENSE.md).
