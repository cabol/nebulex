defmodule Nebulex.Adapters.Nil do
  @moduledoc """
  The **Nil adapter** is a special cache adapter that disables the cache;
  it loses all the items saved on it and it returns `nil` for all the read
  and `true` for all save operations. This adapter is mostly useful for tests.

  ## Example

  Suppose you have an application using Ecto for database access and Nebulex
  for caching. Then, you have defined a cache and a repo within it. Since you
  are using a database, there might be some cases you may want to disable the
  cache to avoid issues when running the test, for example, in some test cases,
  when accessing the database you expect no data at all, but you could retrieve
  the data from cache anyway because maybe it was cached in a previous test.
  Therefore, you have to delete all entries from the cache before to run each
  test to make sure the cache is always empty. This is where the Nil adapter
  comes in, instead of adding code to flush the cache before each test, you
  could define a test cache using the Nil adapter for the tests.

  One one hand, you have defined the cache in your application within
  `lib/my_app/cache.ex`:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  And on the other hand, in the tests you have defined the test cache within
  `test/support/test_cache.ex`:

      defmodule MyApp.TestCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Nil
      end

  Now, we have to tell the app what cache to use depending on the environment,
  for tests we want `MyApp.TestCache`, otherwise it is always `MyApp.Cache`.
  We can do this very easy by introducing a new config parameter to decide
  what cache module to use. For tests you can define the config
  `config/test.exs`:

      config :my_app,
        nebulex_cache: MyApp.TestCache,
        ...

  The final piece is to read the config parameter and start the cache properly.
  Within `lib/my_app/application.ex` you could have:

      def start(_type, _args) do
        children = [
          {Application.get_env(:my_app, :nebulex_cache, MyApp.Cache), []},
        ]

        ...

  As you can see, by default `MyApp.Cache` is always used, unless the
  `:nebulex_cache` option points to a different module, which will be
  when tests are executed (`:test` env).
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable
  @behaviour Nebulex.Adapter.Persistence
  @behaviour Nebulex.Adapter.Stats

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  import Nebulex.Helpers

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_env), do: :ok

  @impl true
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> :ok end}, id: {Agent, 1})
    {:ok, child_spec, %{}}
  end

  ## Nebulex.Adapter.Entry

  @impl true
  def fetch(adapter_meta, key, _) do
    wrap_error Nebulex.KeyError, key: key, cache: adapter_meta.cache
  end

  @impl true
  def get_all(_, _, _), do: {:ok, %{}}

  @impl true
  def put(_, _, _, _, _, _), do: {:ok, true}

  @impl true
  def put_all(_, _, _, _, _), do: {:ok, true}

  @impl true
  def delete(_, _, _), do: :ok

  @impl true
  def take(adapter_meta, key, _) do
    wrap_error Nebulex.KeyError, key: key, cache: adapter_meta.cache
  end

  @impl true
  def exists?(_, _), do: {:ok, false}

  @impl true
  def ttl(adapter_meta, key) do
    wrap_error Nebulex.KeyError, key: key, cache: adapter_meta.cache
  end

  @impl true
  def expire(_, _, _), do: {:ok, false}

  @impl true
  def touch(_, _), do: {:ok, false}

  @impl true
  def update_counter(_, _, amount, _, default, _) do
    {:ok, default + amount}
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  def execute(_, :all, _, _), do: {:ok, []}
  def execute(_, _, _, _), do: {:ok, 0}

  @impl true
  def stream(_, _, _), do: {:ok, Stream.each([], & &1)}

  ## Nebulex.Adapter.Persistence

  @impl true
  def dump(_, _, _), do: :ok

  @impl true
  def load(_, _, _), do: :ok

  ## Nebulex.Adapter.Stats

  @impl true
  def stats(_), do: %Nebulex.Stats{}
end
