defmodule Nebulex do
  @moduledoc ~S"""
  Nebulex is split into 2 main components:

    * `Nebulex.Cache` - caches are wrappers around the in-memory data store.
      Via the cache, we can put, get, update, delete and query existing entries.
      A cache needs an adapter to communicate to the in-memory data store.

    * `Nebulex.Caching` - Declarative annotation-based caching via
      **`Nebulex.Caching.Decorators`**. Decorators provide n elegant way of
      annotating functions to be cached or evicted. Caching decorators also
      enable the usage and/or implementation of cache usage patterns like
      **Read-through**, **Write-through**, **Cache-as-SoR**, etc.
      See [Cache Usage Patterns Guide](http://hexdocs.pm/nebulex/cache-usage-patterns.html).

  In the following sections, we will provide an overview of those components and
  how they interact with each other. Feel free to access their respective module
  documentation for more specific examples, options and configuration.

  If you want to quickly check a sample application using Nebulex, please check
  the [getting started guide](http://hexdocs.pm/nebulex/getting-started.html).

  ## Caches

  `Nebulex.Cache` is the wrapper around the Cache. We can define a
  cache as follows:

      defmodule MyApp.MyCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.MyCache,
        gc_interval: 3_600_000, #=> 1 hr
        backend: :shards,
        partitions: 2

  Each cache in Nebulex defines a `start_link/1` function that needs to be
  invoked before using the cache. In general, this function is not called
  directly, but used as part of your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`) you will have a `lib/my_app/application.ex` file containing
  the application start callback that defines and starts your supervisor.
  You just need to edit the `start/2` function to start the cache as a
  supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.Cache, []}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  Otherwise, you can start and stop the cache directly at any time by calling
  `MyApp.Cache.start_link/1` and `MyApp.Cache.stop/1`.

  ## Declarative annotation-based caching

  See [Nebulex.Caching](http://hexdocs.pm/nebulex/Nebulex.Caching.html).
  """
end
