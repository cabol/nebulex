# Nebulex

[![Build Status](https://travis-ci.org/cabol/nebulex.svg?branch=master)](https://travis-ci.org/cabol/nebulex)
[![Coverage Status](https://coveralls.io/repos/github/cabol/nebulex/badge.svg?branch=master)](https://coveralls.io/github/cabol/nebulex?branch=master)

> **Distributed and Local Caching Tool for Elixir**

**Nebulex** includes:

 - Local Generational Cache
 - Distributed Cache
 - Multilevel Cache (WIP)

 > **WIP** – Check progress [HERE](https://github.com/cabol/nebulex/issues/1)

## Installation

Add `nebulex` to your list dependencies in `mix.exs`:

```elixir
def deps do
  [{:nebulex, github: "cabol/nebulex"}]
end
```

## Usage

1. Define a **Cache** module in your app:

```elixir
defmodule MyApp.LocalCache do
  use Nebulex.Cache, otp_app: :my_app, adapter: Nebulex.Adapters.Local
end
```

2. Start the **Cache** as part of your app supervision tree:

```elixir
defmodule MyApp do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(MyApp.LocalCache, [])
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

3. Configure `MyApp.LocalCache` in your `config.exs`:

```elixir
config :myapp, MyApp.LocalCache,
  adapter: Nebulex.Adapters.Local,
  n_shards: 2,
  gc_interval: 3600
```

Now you're ready to start using it!

## Example

```elixir
alias MyApp.LocalCache

LocalCache.set "foo", "bar", ttl: 2

"bar" = LocalCache.get "foo"

true = LocalCache.has_key? "foo"

%Nebulex.Object{key: "foo", value: "bar"} = LocalCache.get "foo", return: :object

:timer.sleep(2000)

nil = LocalCache.get "foo"

nil = "foo" |> LocalCache.set("bar", return: :key) |> LocalCache.delete
```

## Testing

Testing by default spawns nodes internally for distributed tests.
To run tests that do not require clustering, exclude  the `clustered` tag:

```shell
$ mix test --exclude clustered
```

If you have issues running the clustered tests try running:

```shell
$ epmd -daemon
```

before running the tests.
