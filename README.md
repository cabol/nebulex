# Nebulex
> ### In-Process and Distributed Caching Framework.
> A fast, flexible and powerful distributed caching framework for Elixir.

[![Build Status](https://travis-ci.org/cabol/nebulex.svg?branch=master)](https://travis-ci.org/cabol/nebulex)
[![Coverage Status](https://coveralls.io/repos/github/cabol/nebulex/badge.svg?branch=master)](https://coveralls.io/github/cabol/nebulex?branch=master)
[![Inline docs](http://inch-ci.org/github/cabol/nebulex.svg)](http://inch-ci.org/github/cabol/nebulex)

Nebulex is an in-process and distributed caching framework with a set of
useful and powerful features such as:

  * Inspired by [Ecto][ecto]; simple and fluent API, flexible and
    pluggable architecture (based on adapters).

  * Built-in adapters; supporting local, distributed and multi-level caching.

  * Support for different distributed caching topologies, such as:
    Partitioned, Near, Replicated, etc.

  * Different eviction mechanisms, such as: time-based eviction through
    the expiry time property (`expire_at`) on the cached objects,
    [multi-queue][multi_queue] or [generational caching][generational_caching]
    (built-in local cache), etc.

  * Object versioning (through the `:version` property); enabling
    [Optimistic offline locks][offline_locks].

  * [Pre/Post execution hooks](http://hexdocs.pm/nebulex/hooks.html).

  * Transactions and key-locking (`Nebulex.Adapter.Transaction`).

[ecto]: https://github.com/elixir-ecto/ecto
[multi_queue]: https://en.wikipedia.org/wiki/Cache_replacement_policies#Multi_queue_(MQ)
[generational_caching]: http://fairwaytech.com/2012/09/write-through-and-generational-caching
[offline_locks]: https://martinfowler.com/eaaCatalog/optimisticOfflineLock.html

See the [getting started](http://hexdocs.pm/nebulex/getting-started.html) guide
and the [online documentation](http://hexdocs.pm/nebulex/Nebulex.html).

## Usage

You need to add `nebulex` as a dependency to your `mix.exs` file. However,
in the case you want to use an external (non built-in) cache adapter, you
also have to add the proper dependency to your `mix.exs` file.

The supported caches and their adapters are:

Cache        | Nebulex Adapter                | Dependency
:----------- | :----------------------------- | :-------------------------
Generational | Nebulex.Adapters.Local         | Built-In
Partitioned  | Nebulex.Adapters.Dist          | Built-In
Multi-level  | Nebulex.Adapters.Multilevel    | Built-In
Redis        | NebulexRedisAdapter            | [nebulex_redis_adapter][nebulex_redis_adapter]
Replicated   | NebulexExt.Adapters.Replicated | [nebulex_ext][nebulex_ext]

[nebulex_redis_adapter]: https://github.com/cabol/nebulex_redis_adapter
[nebulex_ext]: https://github.com/amilkr/nebulex_ext

For example, if you want to use a built-in cache, you just need to add
`nebulex` to your `mix.exs` file:

```elixir
def deps do
  [
    {:nebulex, "~> 1.0.0-rc.3"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.

Finally, in the cache definition, you will need to specify the `adapter`
respective to the chosen dependency. For the local built-in cache it is:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app
    adapter: Nebulex.Adapters.Local
  ...
```

> Check out the [getting started](http://hexdocs.pm/nebulex/getting-started.html)
  guide to learn more about it.

## Important links

 * [Documentation](http://hexdocs.pm/nebulex/Nebulex.html)
 * [Examples](https://github.com/cabol/nebulex_examples)
 * [Ecto Integration](https://github.com/cabol/nebulex_ecto)

## Testing

Testing by default spawns nodes internally for distributed tests.
To run tests that do not require clustering, exclude  the `clustered` tag:

```
$ mix test --exclude clustered
```

If you have issues running the clustered tests try running:

```
$ epmd -daemon
```

before running the tests.

## Benchmarks

Simple and/or basic benchmarks were added using [benchfella](https://github.com/alco/benchfella);
to learn more, see the [bench](./bench) directory.

To run the benchmarks:

```
$ mix nebulex.bench
```

If you are interested to run more sophisticated load tests, perhaps you should
checkout the [Nebulex Load Tests](https://github.com/cabol/nebulex_examples/tree/master/nebulex_bench)
example, it allows you to run your own performance/load tests against Nebulex,
and it also comes with load tests results.

## Copyright and License

Copyright (c) 2017, Carlos Bolaños.

Nebulex source code is licensed under the [MIT License](LICENSE).
