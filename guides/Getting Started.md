# Getting Started

This guide is an introduction to [Nebulex](https://github.com/cabol/nebulex),
a local and distributed caching tool for Elixir. Nebulex design and API are
based on [Ecto](https://github.com/elixir-ecto/ecto), taking advantage of its
flexible and pluggable architecture. In the same way as Ecto, developers can
provide their own Cache implementations.

In this guide, we're going to learn some basics about Nebulex, such as setting,
retrieving and destroying cache entries (key/value pairs).

## Adding Nebulex to an application

Let's start creating a new Elixir application by running this command:

```
mix new blog --sup
```

The `--sup` option ensures that this application has [a supervision tree](http://elixir-lang.org/getting-started/mix-otp/supervisor-and-application.html),
which will be needed by Nebulex later on.

To add Nebulex to this application, there are a few steps that we need to take.

1. The first one will be adding Nebulex to our `mix.exs` file, which we'll do by
changing the `deps` definition in that file to this:

```elixir
defp deps do
  [{:nebulex, "~> 1.0"}]
end
```

To install these dependencies, we will run this command:

```
mix deps.get
```

2. Now we need to setup some configuration for Nebulex so that we can perform
actions on a cache from within the application's code.

We can set up this configuration by running this command:

```
mix nebulex.gen.cache -c Blog.LocalCache
```

This command will generate the configuration required to use our cache.
The first bit of configuration is in `config/config.exs`:

```elixir
config :blog, Blog.LocalCache,
  adapter: Nebulex.Adapters.Local,
  gc_interval: 3600
```

The `Blog.LocalCache` module is defined in `lib/blog/local_cache.ex` by our
`mix nebulex.gen.cache` command:

```elixir
defmodule Blog.LocalCache do
  use Nebulex.Cache, otp_app: :blog
end
```

This module is what we'll be using to interact with the cache. It uses the
`Nebulex.Cache` module, and the `otp_app` tells Nebulex which Elixir application
it can look for cache configuration in. In this case, we've specified that it is
the `:blog` application where Nebulex can find that configuration and so Nebulex
will use the configuration that was set up in `config/config.exs`.

3. The final piece of configuration is to setup the `Blog.LocalCache` as a
supervisor within the application's supervision tree, which we can do in
`lib/blog/application.ex` (or `lib/blog.ex` for elixir versions `< 1.4.0`),
inside the `start/2` function:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.LocalCache, []),
  ]

  ...
```

This piece of configuration will start the Nebulex process which receives and
executes our application's commands. Without it, we wouldn't be able to use
the cache at all!

We've now configured our application so that it's able to execute commands
against our cache.

## Using the Cache
