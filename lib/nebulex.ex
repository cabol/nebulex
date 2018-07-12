defmodule Nebulex do
  @moduledoc """
  Nebulex is split into 2 main components:

    * `Nebulex.Cache` - caches are wrappers around the in-memory data store.
      Via the cache, we can insert, retrieve, update and delete entries from
      the in-memory data store. A cache needs an adapter to communicate to
      the in-memory data store.

    * `Nebulex.Object` - this is the struct used by caches to handle data
      back and forth, entries in cache are stored and retrieved as objects,
      but this is totally handled by the cache adapter.

  In the following sections, we will provide an overview of those components and
  how they interact with each other. Feel free to access their respective module
  documentation for more specific examples, options and configuration.

  If you want to quickly check a sample application using Nebulex, please check
  the [getting started guide](http://hexdocs.pm/nebulex/getting-started.html).

  ## Caches

  `Nebulex.Cache` is the wrapper around the Cache. We can define a
  cache as follows:

      defmodule MyApp.MyCache do
        use Nebulex.Cache, otp_app: :my_app
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.MyCache,
        adapter: Nebulex.Adapters.Local,
        n_shards: 2,
        gc_interval: 3600,
        write_concurrency: true

  Each cache in Nebulex defines a `start_link/1` function that needs to be
  invoked before using the cache. In general, this function is not called
  directly, but used as part of your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup` to
  `mix new`) you will have a `lib/my_app.ex` file containing the application
  start callback that defines and starts your supervisor. You just need to
  edit the `start/2` function to start the repo as a supervisor on your
  application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.Cache, []}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ## Object

  `Nebulex.Object` is the struct used by the caches to store and retrieve data.

  By default, when you execute some operation (set, get, delete, etc.) over a
  cache entry, the cache returns only the value of that entry, but you can ask
  for return the whole object:

      iex> MyCache.set "foo", "bar", return: :object
      %Nebulex.Object{key: "foo", ttl: :infinity, value: "bar", version: 1493481403098321000}

      iex> MyCache.get "foo", return: :object
      %Nebulex.Object{key: "foo", ttl: :infinity, value: "bar", version: 1493481403098321000}

  See `Nebulex.Object` to learn more about it.
  """
end
