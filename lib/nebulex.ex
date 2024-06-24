defmodule Nebulex do
  @moduledoc ~S"""
  Nebulex is split into two main components:

    * `Nebulex.Cache` - Defines a standard Cache API for caching data.
      This API implementation is intended to create a way for different
      technologies to provide a common caching interface. It defines the
      mechanism for creating, accessing, updating, and removing information
      from a cache. This common interface makes it easier for software
      developers to leverage various technologies as caches since the
      software they write using the Nebulex Cache API does not need
      to be rewritten to work with different underlying technologies.

    * `Nebulex.Caching` - Defines a Cache Abstraction for transparently adding
      caching into an existing Elixir application. The caching abstraction
      allows consistent use of various caching solutions with minimal impact
      on the code. This Cache Abstraction enables declarative decorator-based
      caching via **`Nebulex.Caching.Decorators`**. Decorators provide an
      elegant way of annotating functions to be cached or evicted. Caching
      decorators also enable the adoption or implementation of cache usage
      patterns such as **Read-through**, **Write-through**, **Cache-as-SoR**,
      etc. See the [Cache Usage Patterns][cache-patterns] guide.

  [cache-patterns]: http://hexdocs.pm/nebulex/cache-usage-patterns.html

  The following sections will provide an overview of those components and their
  usage. Feel free to access their respective module documentation for more
  specific examples, options, and configurations.

  If you want to check a sample application using Nebulex quickly, please check
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
        gc_interval: :timer.hours(1),
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

  ## Declarative decorator-based caching

  See [Nebulex.Caching](http://hexdocs.pm/nebulex/Nebulex.Caching.html).
  """

  ## API

  @doc """
  Returns the current Nebulex version.
  """
  @spec vsn() :: binary()
  def vsn do
    Application.spec(:nebulex, :vsn)
    |> to_string()
  end
end
